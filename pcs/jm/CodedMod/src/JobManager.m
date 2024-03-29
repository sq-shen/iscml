classdef JobManager < handle
    
    properties
        JobManagerParam
        JobManagerInfo
        UserList = []
    end
    
    properties(SetAccess = protected)
        NodeID_Times = []       % NodeID_Times is a vector structure with two fields:
        % NodeID and NumNodeTaskInfo (how many times that specific node has generated TaskInfo (run simulations)).
        % The length of this structure is equal to the number of active nodes (NumNode).
        eTimeProcessUnit = []   % eTimeProcessUnit is a 3-by-MaxRecentTaskInfo-by-NumNode matrix.
        % Its first row contains the time calculated globally from the start of the job manager until receiving curret consumed task from TaskOut directory.
        % Its second row contains elapsed times in current task at the worker and its third row contains the number of trials completed during the eTime at the worker.
    end
    
    
    methods(Static)
        function OldPath = SetCodePath(CodeRoot)
            % Determine the home directory.
            OldPath = path;
            
            addpath( fullfile(CodeRoot, 'mat') );
            % This is the location of the mex directory for this architecture.
            addpath( fullfile( CodeRoot, 'mex', lower(computer) ) );
        end
        
        
        function [JobInDir, JobRunningDir, JobOutDir, JobFailedDir, SuspendedDir, TempDir, DataDir, FiguresDir] = SetPaths(JobQueueRoot)
            % Determine required directories under user's JobQueueRoot.
            JobInDir = fullfile(JobQueueRoot,'JobIn');
            JobRunningDir = fullfile(JobQueueRoot,'JobRunning');
            JobOutDir = fullfile(JobQueueRoot,'JobOut');
            JobFailedDir = fullfile(JobQueueRoot,'JobFailed');
            SuspendedDir = fullfile(JobQueueRoot,'Suspended');
            TempDir = fullfile(JobQueueRoot,'Temp');
            DataDir = fullfile(JobQueueRoot,'Data');
            FiguresDir = fullfile(JobQueueRoot,'Figures');
            % TaskInDir = fullfile(TasksRoot,'TaskIn');
            % TaskOutDir = fullfile(TasksRoot,'TaskOut');
        end
        
        
        function NumNewTasks = FindNumNewTasks(UserParam)
            NumNewTasks = 0;
            % TaskInDir = fullfile(UserParam.TasksRoot,'TaskIn');
            TaskInDir = UserParam.TaskInDir;
            
            % Sense the load of the task input queue (TaskIn directory) of current user.
            DTaskIn = dir( fullfile(TaskInDir,'*.mat') );
            CurrentTaskLoad = length(DTaskIn);
            
            if CurrentTaskLoad <= UserParam.MaxInputTasks % If CurrentTaskLoad>MaxInputTasks, NO NEW TASKs will be generated.
                % As long as CurrentTaskLoad is less than MaxInputTasks, always generate at least one task.
                % If CurrentTaskLoad is less than TaskGenDecelerate, generate MaxTaskGenStep (or TaskGenDecelerate-CurrentTaskLoad) tasks at a time.
                NumNewTasks = max( min( UserParam.MaxTaskGenStep, UserParam.TaskGenDecelerate-CurrentTaskLoad ), 1);
            end
        end
        
        
        function Username = FindUsername(UserPath)
            Username = fliplr( strtok( fliplr(UserPath),filesep ) );
        end
    end
    
    
    methods
        
        function obj = JobManager(cfgRoot, queueCfg, JmName)
            % Calling syntax: obj = JobManager([cfgRoot, queueCfg, JmName])
            % Input cfgRoot is the FULL path to the configuration file of the job manager.
            % Default: cfgRoot = [filesep,'home','pcs','jm',ProjectName,'cfg',CFG_Filename]
            % Input queueCfg specifies queue configuration file.
            % Input JmName specifies job manager name.
            
            % if( nargin<1 || isempty(cfgRoot) ), cfgRoot = []; end
            obj.JobManagerParam = obj.InitJobManager(cfgRoot, JmName);
            obj.JobManagerParam.queueCfg = queueCfg;  % Assign queue config to class property.
            
            obj.JobManagerInfo = obj.InitJobManagerInfo();
            [obj.UserList, obj.JobManagerInfo.UserUsageInfo] = obj.InitUsers();
            
            % Save the job manager parameters, user list, and user usage information.
            JobManagerParam = obj.JobManagerParam;
            JobManagerInfo = obj.JobManagerInfo;
            UserList = obj.UserList;
            try
                save( obj.JobManagerParam.JMInfoFullPath, 'JobManagerParam', 'JobManagerInfo', 'UserList' );
                SuccessMsg = sprintf( '\nJob manager parameters and information containing the user list and user usage information is saved.\n\n' );
                PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
            catch
                [JMInfoPath, JMInfoName, JMInfoExt] = fileparts(obj.JobManagerParam.JMInfoFullPath);
                save( fullfile(obj.JobManagerParam.TempJMDir,[JMInfoName, JMInfoExt]), 'JobManagerParam', 'JobManagerInfo', 'UserList' );
                obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[JMInfoName, JMInfoExt]), JMInfoPath);
                SuccessMsg = sprintf( '\nJob manager parameters and information containing the user list and user usage information is saved by OS.\n\n' );
                PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
            end
            
            Msg = sprintf( '\n\n\nThe list of ACTIVE users is extracted at %s.\n\nThere are %d ACTIVE users in the system.\n\n',...
                datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM'), length(obj.UserList) );
            PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
            
            obj.InitHeartBeat( ); % Initialize heartbeat parameters.
            
            obj.InitQueueInfo( ); % Initialize queue info.
        end
        
        
        function InitHeartBeat( obj )
            % Initialize heartbeat parameters.
            
            heading = '[heartbeat]';
            key = 'hb_path';
            out = util.fp( obj.JobManagerParam.queueCfg, heading, key );
            obj.JobManagerParam.hb_path = out{1}{1};
            
            key = 'hb_period';
            out = util.fp( obj.JobManagerParam.queueCfg, heading, key );
            obj.JobManagerParam.hb_period = str2double(out{1}{1});
        end
        
        
        function InitQueueInfo( obj )
            % Initialize queue information.
            heading = '[paths]';
            key = 'queue_name';
            out = util.fp( obj.JobManagerParam.queueCfg, heading, key );
            obj.JobManagerParam.queue_name = out{1}{1};
        end
        
        
        function heartbeat(obj)
            % Touch heartbeat file to signal task controller status.
            hb_file = fullfile( obj.JobManagerParam.hb_path, [obj.JobManagerParam.JmName '_' obj.JobManagerParam.queue_name] );
            % Touch implemented as file opening and closing.
            HB_FileID = fopen(hb_file, 'w+'); fclose(HB_FileID);
        end
        
        
        function RunJobManager(obj)
            % Main function that runs the whole Job Manager.
            
            % Echo out starting time of running the Job Manager.
            Msg = sprintf( '\nThe JOB MANAGER for the current project started at %s.\n\n', datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
            PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
            
            RunningJobManager = 1;
            RunningUsers = 1;
            
            JMGlobalTimer = tic;   % Global timer of job manager to keep track of timing information of finished tasks.
            
            % Heartbeat parameters.
            TimerHeartBeat = tic;
            HeartBeat_OneShot = 1;
            
            if( exist(obj.JobManagerParam.JMInfoFullPath, 'file') ~= 0 )
                % Load JobManagerParam and JobManagerInfo (containing UserUsageInfo).
                JMInfoFileContent = load( obj.JobManagerParam.JMInfoFullPath, 'JobManagerParam', 'JobManagerInfo', 'UserList' );
                if isfield(JMInfoFileContent, 'JobManagerInfo')
                    obj.JobManagerInfo = JMInfoFileContent.JobManagerInfo;
                end
            end
            
            while RunningJobManager
                
                % Update heartbeat file.
                C1 = HeartBeat_OneShot;
                C2 = toc(TimerHeartBeat) > obj.JobManagerParam.hb_period;
                if( C1 || C2 )
                    obj.heartbeat();
                    TimerHeartBeat = tic;
                    HeartBeat_OneShot = 0;
                end
                
                Check4NewUser = 0;
                Msg = sprintf( '\n\n\nThe list of all ACTIVE users is extracted and updated at %s.\n', datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                [obj.UserList, obj.JobManagerInfo.UserUsageInfo] = obj.InitUsers();
                nActiveUsers = length(obj.UserList);
                Msg = sprintf( 'There are %d ACTIVE users in the system.\n\n\n', nActiveUsers );
                PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                
                % Save the job manager parameters, user list, and user usage information.
                JobManagerParam = obj.JobManagerParam;
                JobManagerInfo = obj.JobManagerInfo;
                UserList = obj.UserList;
                try
                    save( obj.JobManagerParam.JMInfoFullPath, 'JobManagerParam', 'JobManagerInfo', 'UserList' );
                    SuccessMsg = sprintf( '\nJob manager parameters and information containing the user list and user usage information is saved.\n\n' );
                    PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                catch
                    [JMInfoPath, JMInfoName, JMInfoExt] = fileparts(obj.JobManagerParam.JMInfoFullPath);
                    save( fullfile(obj.JobManagerParam.TempJMDir,[JMInfoName, JMInfoExt]), 'JobManagerParam', 'JobManagerInfo', 'UserList' );
                    obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[JMInfoName, JMInfoExt]), JMInfoPath);
                    SuccessMsg = sprintf( '\nJob manager parameters and information containing the user list and user usage information is saved by OS.\n\n' );
                    PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                end
                
                if nActiveUsers>0
                    
                    while RunningUsers
                        Check4NewUser = Check4NewUser + 1;
                        
                        UserInfoFileUpdated = 0;
                        
                        for User = 1:nActiveUsers
                            CurrentUser = obj.UserList(User);
                            % [HomeRoot, Username, Extension, Version] = fileparts(CurrentUser.UserPath);
                            % [Dummy, Username] = fileparts(CurrentUser.UserPath);
                            Username = obj.FindUsername(CurrentUser.UserPath);
                            
                            [JobInDir, JobRunningDir, JobOutDir, JobFailedDir, SuspendedDir, TempDir, DataDir, FiguresDir] = obj.SetPaths(CurrentUser.JobQueueRoot);
                            TaskInDir = CurrentUser.TaskInDir;
                            TaskOutDir = CurrentUser.TaskOutDir;
                            
                            DJobInCurrentUser = dir( fullfile(JobInDir,'*.mat') );
                            DJobRunningCurrentUser = dir( fullfile(JobRunningDir,'*.mat') );
                            DTaskOutCurrentUser = dir( fullfile(TaskOutDir,[obj.JobManagerParam.ProjectName '_*.mat']) );
                            if ~( isempty(DJobInCurrentUser) && isempty(DJobRunningCurrentUser) && isempty(DTaskOutCurrentUser) )
                                
                                TotalUserCount = length(obj.JobManagerInfo.UserUsageInfo);
                                CurrentUserInfoFlag = zeros(TotalUserCount,1);
                                for v = 1:TotalUserCount
                                    CurrentUserInfoFlag(v) = strcmpi( obj.JobManagerInfo.UserUsageInfo(v).Username, Username );
                                end
                                
                                CurrentUserUsageInfo = obj.JobManagerInfo.UserUsageInfo(CurrentUserInfoFlag==1);
                                
                                CurrentUser.TaskID = CurrentUserUsageInfo.TaskID;
                                
                                %******************************************************************
                                % MONITOR THE JOB INPUT AND JOB RUNNING QUEUES/DIRECTORIES OF CURRENT USER.
                                %******************************************************************
                                
                                % Determine the number of new tasks to be generated for the current user.
                                % If no new tasks can be generated skip this part.
                                NumNewTasks = obj.FindNumNewTasks(CurrentUser);
                                
                                if NumNewTasks > 0
                                    
                                    % Look to see if there are any new .mat files in JobInDir and old .mat files in JobRunningDir.
                                    if NumNewTasks > 1
                                        SuccessMsgIn = sprintf( '\nLAUNCHING simulation for user %s NEW job at %s.\n\n', ...
                                            Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                        SuccessMsgRunning = sprintf( '\nCONTINUING simulation for user %s at %s by FURTHER generation of its tasks.\n\n', ...
                                            Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                        NoJobMsg = sprintf( '\nNo new tasks for user %s was generated at %s. Both JobIn and JobRunning directories are emty of job files.\n\n', ...
                                            Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                    else
                                        SuccessMsgIn = [];
                                        SuccessMsgRunning = [];
                                        NoJobMsg = [];
                                    end
                                    [JobDirectory, JobNameCell] = obj.SelectInRunningJob(JobInDir, JobRunningDir, CurrentUser.MaxRunningJobs, SuccessMsgIn, SuccessMsgRunning, NoJobMsg);
                                    
                                    if ~isempty(JobNameCell)
                                        for JobNum=1:length(JobNameCell)
                                        JobName = JobNameCell{JobNum};
                                        % Try to load the selected input job.
                                        SuccessMsg = sprintf( 'Input job file %s for user %s is loaded at %s.\n\n',...
                                            JobName(1:end-4), Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                        
                                        if strcmpi( JobDirectory, JobInDir )
                                            % Increment the counter of JobID since a new job is being served.
                                            obj.JobManagerInfo.JobID = obj.JobManagerInfo.JobID + 1;
                                            
                                            % Load the input job file.
                                            JLSuccessFlag = 0;
                                            ErrorMsg = '';
                                            try
                                                JobContent = load( fullfile(JobDirectory,JobName), 'JobParam', 'JobState' );
                                                if( isfield(JobContent,'JobParam') && isfield(JobContent,'JobState') )
                                                    JLSuccessFlag = 1;
                                                    % Set success/error messages.
                                                else
                                                    % Print error message regarding job loading.
                                                    Msg1 = sprintf('Input job file %s of user %s ', JobName(1:end-4), Username );
                                                    Msg2 = 'does not contain JobParam and JobState.';
                                                    ErrorMsg = [Msg1 Msg2];
                                                end
                                            catch
                                                % Print error message regarding job loading.
                                                Msg1 = 'Type-ONE Error (Job Load Error): ';
                                                Msg2 = sprintf('Input job file %s of user %s could not be loaded. ', JobName(1:end-4), Username );
                                                Msg3 = sprintf('It will be deleted automatically.\n');
                                                Msg4 = 'Input job should be a .mat file containing two MATLAB structures named JobParam and JobState.';
                                                ErrorMsg = [Msg1 Msg2 Msg3 Msg4];
                                            end
                                            
                                            % Initialize the JobInfo structure.
                                            JobInfo = obj.InitJobInfo();
                                            % Set the JobID.
                                            JobInfo = obj.UpdateJobInfo(JobInfo, 'JobID', obj.JobManagerInfo.JobID);
                                            
                                            % Preprocess job if job loading is successful.
                                            PPSuccessFlag = 0;
                                            if JLSuccessFlag == 1,
                                                JobParam = JobContent.JobParam;
                                                JobState = JobContent.JobState;
                                                [JobParam, JobState, JobInfo, PPSuccessFlag, PPErrorMsg] = obj.PreProcessJob(JobParam, JobState, JobInfo, CurrentUser, JobName);
                                                % Set success/error message.
                                                if ~isempty(PPErrorMsg)
                                                    ErrorMsg = [ErrorMsg sprintf('\n\n') PPErrorMsg];
                                                end
                                            end
                                            
                                            % All load and preprocessing steps must be successful for job execution.
                                            SuccessFlag = JLSuccessFlag & PPSuccessFlag;
                                            
                                            if SuccessFlag == 1
                                                PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                                            else % Input job was bad, kick out of loading loop.
                                                JobContent = [];
                                                PrintOut(ErrorMsg, 0, obj.JobManagerParam.LogFileName);
                                            end
                                        elseif strcmpi( JobDirectory, JobRunningDir )
                                            if ~exist('ErrorMsg', 'var'),
                                                ErrorMsg = '';
                                            end
                                            [JobContent, SuccessFlag] = obj.LoadFile(fullfile(JobDirectory,JobName), 'JobParam', 'JobState', 'JobInfo', SuccessMsg, ErrorMsg);
                                        end
                                        
                                        if SuccessFlag == 1
                                            if strcmpi( JobDirectory, JobInDir )
                                                % Pre-process the job read from the JobIn directory.
                                                %[JobParam, JobState, JobInfo, PPSuccessFlag, PPErrorMsg] = obj.PreProcessJob(JobParam, JobState, JobInfo, CurrentUser, JobName);
                                                
                                                StartTime = datenum(clock);
                                                % Set the job StartTime in the JobInfo structure.
                                                JobInfo = obj.UpdateJobInfo(JobInfo, 'StartTime', StartTime);
                                                
                                                % Set the JobID and StartTime in the global UserUsageInfo structure.
                                                CurrentUserUsageInfo.UserUsage(1,end) = obj.JobManagerInfo.JobID;
                                                CurrentUserUsageInfo.UserUsage(2,end) = StartTime;
                                                CurrentUserUsageInfo.UserUsage = [CurrentUserUsageInfo.UserUsage, zeros(4,1)];
                                            elseif strcmpi( JobDirectory, JobRunningDir )
                                                JobParam = JobContent.JobParam;
                                                JobState = JobContent.JobState;
                                                JobInfo = JobContent.JobInfo;
                                            end
                                        else
                                            % Selected input job file was bad. Issue an error and exit loading loop.
                                            Msg = sprintf( ['ErrorType=1\r\nErrorMsg=Job Load Error: Input job file %s could not be loaded. It will be deleted automatically.',...
                                                'Input job should be a .mat file containing two MATLAB structures named JobParam and JobState.'], JobName(1:end-4) );
                                            if ~isempty(ErrorMsg)
                                                Msg = sprintf('%s \n %s', Msg, ErrorMsg);
                                            end
                                            % SuccessFlagResults = obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'w+');
                                            % obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'w+');
                                            JobInfo = obj.InitJobInfo();
                                            JobInfo = obj.UpdateJobInfo(JobInfo, 'JobID', obj.JobManagerInfo.JobID, 'ErrorType', 1, 'ErrorMsg', Msg);
                                            
                                            % Save the corrupted input/running job file in JobFailed directory with its error information.
                                            try
                                                save( fullfile(JobFailedDir,JobName), 'JobInfo' );
                                                SuccessMsg = sprintf( 'Corrupted input/running job file %s of user %s is moved from its JobIn/JobRunning to its JobFailed directory with error information.\n', JobName(1:end-4), Username );
                                                PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                                            catch
                                                save( fullfile(obj.JobManagerParam.TempJMDir,JobName), 'JobInfo' );
                                                SuccessMsg = sprintf( 'Corrupted input/running job file %s of user %s is moved from its JobIn/JobRunning to its JobFailed directory with error information by OS.\n', JobName(1:end-4), Username );
                                                obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,JobName), JobFailedDir, SuccessMsg);
                                            end
                                        end
                                        
                                        % Delete or copy (to JobRunning directory) the selected input job file from JobIn directory.
                                        if strcmpi( JobDirectory, JobInDir )
                                            if SuccessFlag ==1
                                                
                                                % If processing the job read from the JobIn directory does not need generating any tasks and can be performed
                                                % in the preprocessing stage, save the results of its running in the JobOut directory.
                                                if( isfield(JobState, 'JobStatus') && ~isempty(JobState.JobStatus) && strcmpi(JobState.JobStatus,'Done') )
                                                    
                                                    % Set the job StartTime and ProcessDuration.
                                                    JobInfo = obj.UpdateJobInfo( JobInfo, 'StartTime', JobState.JobInfo.StartTime, ...
                                                        'ProcessDuration', etime(JobState.TaskInfo.StopTime, JobState.TaskInfo.StartTime) );
                                                    JobState = rmfield(JobState, {'JobStatus','JobInfo','TaskInfo'});
                                                    
                                                    % Determine if the global stopping criteria have been reached/met.
                                                    % Moreover, determine and echo the progress of running JobName.
                                                    % Furthermore, update Results file.
                                                    [StopFlag, JobInfo, JobParam, JobState] = obj.DetermineStopFlag(JobParam, JobState, JobInfo, JobName, Username, FiguresDir);
                                                    if StopFlag % If simulation of this job is done, save the result in JobOut queue/directory.
                                                        % Set the job StopTime.
                                                        StopTime = datenum(clock);
                                                        JobInfo = obj.UpdateJobInfo(JobInfo, 'StopTime', StopTime, 'Status', 'Done');
                                                        
                                                        % Put a copy of the FINISHED input job into JobOut directory and delete it from JobIn directory.
                                                        try
                                                            save( fullfile(JobOutDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                            Msg1 = sprintf( 'The FINISHED INPUT job file %s of user %s is moved ', JobName(1:end-4), Username );
                                                            Msg2 = sprintf('from its JobIn to its JobRunning directory since it was fully processed by the job manager.\n');
                                                            SuccessMsg = [Msg1 Msg2];
                                                            PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                                                        catch
                                                            save( fullfile(obj.JobManagerParam.TempJMDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                            obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,JobName), JobOutDir);
                                                            Msg1 = sprintf( 'The FINISHED INPUT job file %s of user %s is moved ', JobName(1:end-4), Username );
                                                            Msg2 = sprintf('from its JobIn to its JobRunning directory by OS since it was fully processed by the job manager.\n');
                                                            SuccessMsg = [Msg1 Msg2];
                                                            PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                                                        end
                                                        % Remove the finished job from JobIn queue/directory.
                                                        obj.DeleteFile( fullfile(JobInDir,JobName) );
                                                    end
                                                    
                                                    % Set the job StartTime in the global UserUsageInfo structure.
                                                    UserAllJobIDs = CurrentUserUsageInfo.UserUsage(1,:);
                                                    CurrentUserUsageInfo.UserUsage(2,UserAllJobIDs == JobInfo.JobID) = ...
                                                        datenum(JobInfo.JobTiming.StartTime, 'ddd., mmm dd, yyyy HH:MM:SS PM');
                                                    % Set the job StopTime in the global UserUsageInfo structure.
                                                    CurrentUserUsageInfo.UserUsage(3,UserAllJobIDs == JobInfo.JobID) = StopTime;
                                                    % Update the current job's ProcessDuration in the global UserUsageInfo structure.
                                                    CurrentUserUsageInfo.UserUsage(4,UserAllJobIDs == JobInfo.JobID) = JobInfo.JobTiming.ProcessDuration;
                                                    CurrentUserUsageInfo.TotalProcessDuration = sum( CurrentUserUsageInfo.UserUsage(4,:) );
                                                    UserInfoFileUpdated = 1;
                                                
                                                else
                                                
                                                % Put a copy of the selected input job into JobRunning directory and delete it from JobIn directory.
                                                try
                                                    save( fullfile(JobRunningDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                    SuccessMsg = sprintf( 'Input job file %s of user %s is moved from its JobIn to its JobRunning directory.\n', JobName(1:end-4), Username );
                                                    PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                                                    obj.DeleteFile( fullfile(JobInDir,JobName) );
                                                catch
                                                    save( fullfile(obj.JobManagerParam.TempJMDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                    SuccessMsg = sprintf( 'Input job file %s of user %s is moved from its JobIn to its JobRunning directory by OS.\n', JobName(1:end-4), Username );
                                                    % If could not move the selected input job file from JobIn to JobRunning directory, just issue a warning.
                                                    ErrorMsg = sprintf( ['Type-ONE Warning (Job Moving Warning): Input job file %s of user %s could not be moved from the user JobIn to its JobRunning directory.\n',...
                                                        'The user can delete the .mat job file manually.'], JobName(1:end-4), Username );
                                                    mvSuccess = obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,JobName), JobRunningDir, SuccessMsg, ErrorMsg);
                                                    if mvSuccess == 0
                                                        Msg = sprintf( ['WarningType=1\r\nWarningMsg=Input job file %s could not be moved from JobIn to JobRunning directory.',...
                                                            'The user can delete the .mat job file manually.'], JobName(1:end-4) );
                                                        % SuccessFlagResults = obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                                        % obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                                        JobInfo = obj.UpdateJobInfo(JobInfo, 'WarningType', 1, 'WarningMsg', Msg);
                                                    else
                                                        obj.DeleteFile( fullfile(JobInDir,JobName) );
                                                    end
                                                end
                                                end
                                            else
                                                T = obj.JobManagerParam.vqFlag;
                                                obj.JobManagerParam.vqFlag = 0;
                                                SuccessMsg = sprintf( 'Input job file %s of user %s is deleted.\n', JobName(1:end-4), Username );
                                                % If could not delete the selected input job file from JobIn directory, just issue a warning.
                                                ErrorMsg = sprintf( ['Type-TWO Warning (Job Delete Warning): Input job file %s of user %s could not be deleted from the user JobIn directory.\n',...
                                                    'The user can delete the .mat job file manually.'], JobName(1:end-4), Username );
                                                obj.DeleteFile( fullfile(JobInDir,JobName), SuccessMsg, ErrorMsg );
                                                obj.JobManagerParam.vqFlag = T;
                                                % Msg = sprintf( ['WarningType=2\r\nWarningMsg=Input job file %s could not be deleted from JobIn directory.',...
                                                %     'The user can delete the .mat job file manually.'], JobName(1:end-4) );
                                                % SuccessFlagResults = obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                                % obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                            end
                                        end
                                        
                                        if SuccessFlag == 1
                                            % Determine the running time for each task.
                                            if strcmpi( JobDirectory, JobInDir )
                                                TaskMaxRunTime = CurrentUser.InitialRunTime;
                                            elseif strcmpi( JobDirectory, JobRunningDir )
                                                if( isfield(JobParam, 'MaxRunTime') && (JobParam.MaxRunTime ~= -1) )
                                                    TaskMaxRunTime = JobParam.MaxRunTime;
                                                else
                                                    TaskMaxRunTime = CurrentUser.MaxRunTime;
                                                end
                                            end
                                            
                                            % This flag is used to prevent generating new tasks for a new INPUT job
                                            % while the first round of generated tasks are not returned yet.
                                            TimeFromFirstTaskGenRound =  etime(clock, datevec(JobInfo.JobTiming.StartTime,'ddd., mmm dd, yyyy HH:MM:SS PM'));
                                            if( strcmpi( JobDirectory, JobInDir ) || (TimeFromFirstTaskGenRound > 1.2*CurrentUser.InitialRunTime) )
                                                
                                                % Divide the JOB into multiple TASKs.
                                                [CurrentUser.TaskID, JobState] = obj.DivideJob2Tasks(JobParam, JobState, CurrentUser, NumNewTasks, JobName, TaskMaxRunTime);
                                                
                                                if( isfield(JobState, 'JobFileUpdateRequest') && ~isempty(JobState.JobFileUpdateRequest) &&...
                                                        JobState.JobFileUpdateRequest == 1 )
                                                JobState = rmfield(JobState, {'JobFileUpdateRequest'});
                                                % Update the copy of the selected job in the JobRunning directory. The JobState has been updated.
                                                try
                                                    save( fullfile(JobRunningDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                    % SuccessMsg = sprintf( '\nRunning job file %s of user %s is UPDATED in its JobRunning directory.\n', JobName(1:end-4), Username );
                                                    % PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                                                catch
                                                    save( fullfile(obj.JobManagerParam.TempJMDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                    % SuccessMsg = sprintf( 'Running job file %s of user %s is UPDATED in its JobRunning directory by OS.\n', JobName(1:end-4), Username );
                                                    SuccessMsg = [];
                                                    TempvgFlag = obj.JobManagerParam.vqFlag;
                                                    obj.JobManagerParam.vqFlag = 0;
                                                    obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,JobName), JobRunningDir, SuccessMsg);
                                                    obj.JobManagerParam.vqFlag = TempvgFlag;
                                                end
                                                end
                                                
                                                if NumNewTasks > 1
                                                    % Done!
                                                    % Msg = sprintf( '\n\nDividing Input/Running job %s to tasks for user %s is done at %s. Waiting for its next job or next job division! ...\n\n',...
                                                    %     JobName(1:end-4), Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                                    % PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                                                end
                                            end
                                        end
                                        end
                                    end
                                end
                                
                                %******************************************************************
                                % MONITOR THE TASK OUTPUT QUEUE/DIRECTORY OF CURRENT USER.
                                %******************************************************************
                                
                                % Look to see if there are any .mat files in TaskOut directory.
                                DTaskOut = dir( fullfile(TaskOutDir,[obj.JobManagerParam.ProjectName '_*.mat']) );
                                NumTaskOut = length(DTaskOut);
                                
                                % Delete ALL FAILED TASKs before further processing.
                                FailedTaskInd = zeros(NumTaskOut,1);
                                for Ta = 1:NumTaskOut
                                    FailedTaskInd(Ta) = ~isempty(strfind( DTaskOut(Ta).name, '_failed' ));
                                    if FailedTaskInd(Ta) == 1
                                        obj.DeleteFile( fullfile(TaskOutDir,DTaskOut(Ta).name) );
                                        Msg = sprintf( 'FAILED output TASK file %s of user %s is deleted at %s.\n',...
                                            DTaskOut(Ta).name(1:end-4), Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                        PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                                    end
                                end
                                DTaskOut(FailedTaskInd == 1) = [];
                                
                                if ~isempty(DTaskOut)
                                    
                                    TaskOutFileIndexTotal = obj.FindFinishedTask2Read(length(DTaskOut));
                                    DTaskOutTotal = DTaskOut;
                                    
                                    for Task2BeReadNum = 1:length(TaskOutFileIndexTotal)
                                    
                                    TaskOutFileIndex = TaskOutFileIndexTotal(Task2BeReadNum);
                                    if ~isempty( dir( fullfile(TaskOutDir,DTaskOutTotal(TaskOutFileIndex).name) ) )
                                    DTaskOut = DTaskOutTotal;
                                    % Construct the finished task filename and the corresponding JobName.
                                    TaskOutFileName = DTaskOut(TaskOutFileIndex).name;
                                    JobName = [TaskOutFileName( regexpi(TaskOutFileName, [obj.JobManagerParam.ProjectName '_'],'end')+1 : ...
                                        regexpi(TaskOutFileName, '_Task_') - 1) '.mat'];
                                    
                                    % Try to load the selected output task file.
                                    SuccessMsg = sprintf( 'Output finished task file %s of user %s is loaded at %s.\n',...
                                        TaskOutFileName(1:end-4), Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                    ErrorMsg = sprintf( ['Type-THREE Warning (Output Task Load Warning): Output task file %s of user %s could not be loaded and will be deleted automatically.\n',...
                                        'Output task should be a .mat file containing two MATLAB structures named TaskParam and TaskState.'], TaskOutFileName(1:end-4), Username );
                                    % Msg = sprintf( ['WarningType=3\r\nWarningMsg=Output task file %s could not be loaded and will be deleted automatically.',...
                                    %     'Output task should be a .mat file containing two MATLAB structures named TaskParam and TaskState.'], TaskOutFileName(1:end-4) );
                                    % SuccessFlagResults = obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                    % obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                    [TaskContent, TaskSuccess] = obj.LoadFile(fullfile(TaskOutDir,TaskOutFileName), 'TaskParam', 'TaskState', 'TaskInfo', SuccessMsg, ErrorMsg);
                                    
                                    if ~isempty(TaskContent)
                                        CurrentTime = toc(JMGlobalTimer); % Keep track of the global time at which the finished task is loaded.
                                        
                                        TaskInputParam = TaskContent.TaskParam.InputParam;
                                        TaskState = TaskContent.TaskState;
                                        TaskInfo = TaskContent.TaskInfo;
                                    end
                                    
                                    % Delete the selected output task file from TaskOut directory.
                                    % if TaskSuccess == 1
                                    SuccessMsg = sprintf( 'The selected output task file %s of user %s is deleted from its TaskOut directory.\n', TaskOutFileName(1:end-4), Username );
                                    % If could not delete output task file, just issue a warning.
                                    ErrorMsg = sprintf( ['Type-FOUR Warning (Output Task Delete Warning): Output task file %s of user %s could not be deleted',...
                                        'from user TaskOut directory.\nThe user can delete the .mat output task file manually.\n'], TaskOutFileName(1:end-4), Username );
                                    obj.DeleteFile( fullfile(TaskOutDir,TaskOutFileName), SuccessMsg, ErrorMsg );
                                    % Msg = sprintf( ['WarningType=4\r\nWarningMsg=Output task file %s could not be deleted from TaskOut directory.',...
                                    %     'The user can delete the .mat output task file manually.'], TaskOutFileName(1:end-4) );
                                    % SuccessFlagResults = obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                    % obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                    PrintOut({'' ; '-'}, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                                    % end
                                    
                                    % Try to load the correspoding JOB file from the user's JobRunning or JobOut directory (if it is there).
                                    
                                    % If the corresponding job file in JobRunning or JobOut directory was bad or nonexistent, kick out of its loading loop.
                                    % This is a method of KILLING a job.
                                    successJR = 0;
                                    if(TaskSuccess == 1)
                                        ErrorMsg = sprintf( ['Type-TWO Error (Invalid/Nonexistent Running or Output Job Error): ',...
                                            'The corresponding job file %s of user %s could not be loaded/does not exist from/in JobRunning or JobOut directory.\n',...
                                            'All corresponding task files will be deleted from TaskIn and TaskOut directories.\n',...
                                            'Job files in JobRunning and JobOut directories should be .mat files containing two MATLAB structures named JobParam and JobState.'],...
                                            JobName(1:end-4), Username );
                                        JobDirectory = obj.FindRunningOutJob(JobRunningDir, JobOutDir, JobName, ErrorMsg);
                                        
                                        if ~isempty(JobDirectory)
                                            if strcmpi(JobDirectory,JobOutDir)
                                                Msg = sprintf( 'Finished JOB %s of user %s is updated in its JobOut directory.\n\n', JobName(1:end-4), Username );
                                                PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                                                strMsg = 'JobOut';
                                            elseif strcmpi(JobDirectory,JobRunningDir)
                                                strMsg = 'JobRunning';
                                            end
                                            
                                            SuccessMsg = sprintf( ['The corresponding job file %s of user %s is loaded from its ', strMsg, ' directory.\n'], JobName(1:end-4), Username );
                                            [JobContent, successJR] = obj.LoadFile(fullfile(JobDirectory,JobName), 'JobParam', 'JobState', 'JobInfo', SuccessMsg, ErrorMsg);
                                            if(successJR == 1)
                                                JobParam = JobContent.JobParam;
                                                JobState = JobContent.JobState;
                                                JobInfo = JobContent.JobInfo;
                                                
                                                if( isfield(JobParam, 'ProfileSpeed') && JobParam.ProfileSpeed == 1 && ...
                                                        sum( isfield(TaskInfo, {'StartTime', 'StopTime'}) )==2 )
                                                    % Update completed TRIALS and required elapsed time for the corresponding NODE that has finished the task. Save Timing Info.
                                                    NumProcessUnit = obj.FindNumProcessUnits(TaskState);
                                                    [NodeID_Times, eTimeProcessUnit] = obj.ExtractETimeProcessUnit( TaskInfo, CurrentTime, NumProcessUnit );
                                                    SpeedProfile = obj.FindSpeedProfileInfo(eTimeProcessUnit);
                                                    JobInfo = obj.UpdateJobInfo( JobInfo, 'SpeedProfile', SpeedProfile );
                                                    try
                                                        save( fullfile(TempDir,[JobName(1:end-4) '_eTimeProcessUnit.mat']), 'eTimeProcessUnit', 'NodeID_Times' );
                                                        SuccessMsg = sprintf( 'Timing information for the NODE that has finished the task is saved for task %s and user %s.\n', TaskOutFileName(1:end-4), Username );
                                                        PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                                                    catch
                                                        save( fullfile(obj.JobManagerParam.TempJMDir,[JobName(1:end-4) '_eTimeProcessUnit.mat']), 'eTimeProcessUnit', 'NodeID_Times' );
                                                        SuccessMsg = sprintf( 'Timing information for the NODE that has finished the task is saved for task %s and user %s by OS.\n', TaskOutFileName(1:end-4), Username );
                                                        obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[JobName(1:end-4) '_eTimeProcessUnit.mat']), TempDir, SuccessMsg);
                                                        save( fullfile(obj.JobManagerParam.TempJMDir,'eTimeProcessUnit.mat'), 'eTimeProcessUnit', 'NodeID_Times' );
                                                    end
                                                end
                                                
                                                % Update JobState if the received output Task has done some trials.
                                                % if sum(TaskState.Trials(end,:))~=0
                                                % JobState = obj.UpdateJobState(JobState, TaskState);
                                                if sum( isfield(TaskInfo, {'StartTime', 'StopTime'}) )==2
                                                    JobState = obj.UpdateJobState(JobState, TaskState, JobParam);
                                                    JobInfo = obj.UpdateJobInfo( JobInfo, 'ProcessDuration', etime(TaskInfo.StopTime, TaskInfo.StartTime) );
                                                    UserAllJobIDs = CurrentUserUsageInfo.UserUsage(1,:);
                                                    CurrentUserUsageInfo.UserUsage(4,UserAllJobIDs == JobInfo.JobID) = JobInfo.JobTiming.ProcessDuration;
                                                    CurrentUserUsageInfo.TotalProcessDuration = sum( CurrentUserUsageInfo.UserUsage(4,:) );
                                                    UserInfoFileUpdated = 1;
                                                end
                                                % else
                                                % Msg = sprintf( 'Task %s of user %s had done NO TRIALS.\n', TaskOutFileName(1:end-4), Username );
                                                % PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                                                % end
                                            end
                                        end
                                        
                                        if( (~isempty(JobDirectory) && successJR == 0) || isempty(JobDirectory) )
                                            % The corresponding job file in JobRunning or JobOut directory was bad or nonexistent. Kick out of its loading loop.
                                            % This is a method of KILLING a job.
                                            Msg = sprintf( ['ErrorType=2\r\nErrorMsg=The corresponding job file %s could not be loaded from JobRunning or JobOut directory',...
                                                'and will be deleted automatically. All corresponding task files will be deleted from TaskIn and TaskOut directories.',...
                                                'Job files in JobRunning and JobOut directories should be .mat files containing two MATLAB structures named JobParam and JobState.'],...
                                                JobName(1:end-4) );
                                            % SuccessFlagResults = obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'w+');
                                            % obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'w+');
                                            
                                            JobInfo = obj.InitJobInfo();
                                            JobInfo = obj.UpdateJobInfo(JobInfo, 'ErrorType', 2, 'ErrorMsg', Msg);
                                            
                                            % Destroy/Delete any other input and output task files associated with this job from TaskIn and TaskOut directories.
                                            if ~isempty( dir( fullfile(TaskInDir, [obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']) ) )
                                                obj.DeleteFile( fullfile(TaskInDir, [obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']) );
                                            end
                                            if ~isempty( dir( fullfile(TaskOutDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']) ) )
                                                obj.DeleteFile( fullfile(TaskOutDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']) );
                                            end
                                        end
                                    end
                                    
                                    if successJR == 1
                                        % Look to see if there are any more related finished .mat task files with the loaded JOB file in TaskOut directory.
                                        DTaskOut = dir( fullfile(TaskOutDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']) );
                                        
                                        for TaskOutFileIndex = 1:length(DTaskOut) % Pick finished task files one by one in order of listing.
                                            % Construct the filename.
                                            TaskOutFileName = DTaskOut(TaskOutFileIndex).name;
                                            
                                            % Try to load the selected output task file.
                                            SuccessMsg = sprintf( '\nOutput finished task file %s of user %s is loaded at %s.\n', ...
                                                TaskOutFileName(1:end-4), Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                            ErrorMsg = sprintf( ['Type-THREE Warning (Output Task Load Warning): Output task file %s of user %s could not be loaded and will be deleted automatically.\n',...
                                                'Output task should be a .mat file containing two MATLAB structures named TaskParam and TaskState.'], TaskOutFileName(1:end-4), Username );
                                            % Msg = sprintf( ['WarningType=3\r\nWarningMsg=Output task file %s could not be loaded and will be deleted automatically.',...
                                            %     'Output task should be a .mat file containing two MATLAB structures named TaskParam and TaskState.'], TaskOutFileName(1:end-4) );
                                            % SuccessFlagResults = obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                            % obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                            [TaskContent, TaskSuccess] = obj.LoadFile(fullfile(TaskOutDir,TaskOutFileName), 'TaskParam', 'TaskState', 'TaskInfo', SuccessMsg, ErrorMsg);
                                            
                                            if ~isempty(TaskContent)
                                                CurrentTime = toc(JMGlobalTimer); % Keep track of the global time at which the finished task is loaded.
                                                
                                                TaskInputParam = TaskContent.TaskParam.InputParam;
                                                TaskState = TaskContent.TaskState;
                                                TaskInfo = TaskContent.TaskInfo;
                                                % TaskInfo.Trials = TaskState.Trials(end,:);
                                                
                                                % Update JobState if the received Task has done some trials.
                                                % if sum(TaskState.Trials(end,:))~=0
                                                % JobState = obj.UpdateJobState(JobState, TaskState);
                                                if sum( isfield(TaskInfo, {'StartTime', 'StopTime'}) )==2
                                                    JobState = obj.UpdateJobState(JobState, TaskState, JobParam);
                                                    JobInfo = obj.UpdateJobInfo( JobInfo, 'ProcessDuration', etime(TaskInfo.StopTime, TaskInfo.StartTime) );
                                                end
                                                % else
                                                % Msg = sprintf( 'Task %s of user %s had done NO TRIALS.\n', TaskOutFileName(1:end-4), Username );
                                                % PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                                                % end
                                                
                                                if( isfield(JobParam, 'ProfileSpeed') && JobParam.ProfileSpeed == 1 && ...
                                                        sum( isfield(TaskInfo, {'StartTime', 'StopTime'}) )==2 )
                                                    % Update completed TRIALS and required elapsed time for the corresponding NODE that has finished the task. Save Timing Info.
                                                    NumProcessUnit = obj.FindNumProcessUnits(TaskState);
                                                    [NodeID_Times, eTimeProcessUnit] = obj.ExtractETimeProcessUnit( TaskInfo, CurrentTime, NumProcessUnit );
                                                end
                                            end
                                            
                                            % Delete the selected output task file from TaskOut directory.
                                            % if TaskSuccess == 1
                                            SuccessMsg = sprintf( 'The selected output task file %s of user %s is deleted from its TaskOut directory.\n', TaskOutFileName(1:end-4), Username );
                                            % If could not delete output task file, just issue a warning.
                                            ErrorMsg = sprintf( ['Type-FOUR Warning (Output Task Delete Warning): Output task file %s of user %s ',...
                                                'could not be deleted from user TaskOut directory.\nThe user can delete the .mat output task file manually.\n'],...
                                                TaskOutFileName(1:end-4), Username );
                                            obj.DeleteFile( fullfile(TaskOutDir,TaskOutFileName), SuccessMsg, ErrorMsg );
                                            % Msg = sprintf( ['WarningType=4\r\nWarningMsg=Output task file %s could not be deleted from TaskOut directory.',...
                                            %     'The user can delete the .mat output task file manually.'], TaskOutFileName(1:end-4) );
                                            % SuccessFlagResults = obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                            % obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Results.txt'], Msg, 'a+');
                                            
                                            PrintOut({'' ; '-'}, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                                            if( rem(TaskOutFileIndex,CurrentUser.TaskInFlushRate)==0 )
                                                PrintOut('\n', 0, obj.JobManagerParam.LogFileName);
                                            end
                                            % end
                                            
                                            % Wait briefly before looping for reading the next finished task file from TaskOut directory.
                                            pause( 0.1*CurrentUser.PauseTime );
                                        end
                                        
                                        if( isfield(JobParam, 'ProfileSpeed') && JobParam.ProfileSpeed == 1 )
                                            SpeedProfile = obj.FindSpeedProfileInfo(eTimeProcessUnit);
                                            JobInfo = obj.UpdateJobInfo( JobInfo, 'SpeedProfile', SpeedProfile );
                                            try
                                                save( fullfile(TempDir,[JobName(1:end-4) '_eTimeProcessUnit.mat']), 'eTimeProcessUnit', 'NodeID_Times' );
                                                SuccessMsg = sprintf( 'Timing information for the NODE that has finished the task is saved for task %s and user %s.\n', TaskOutFileName(1:end-4), Username );
                                                PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                                            catch
                                                save( fullfile(obj.JobManagerParam.TempJMDir,[JobName(1:end-4) '_eTimeProcessUnit.mat']), 'eTimeProcessUnit', 'NodeID_Times' );
                                                SuccessMsg = sprintf( 'Timing information for the NODE that has finished the task is saved for task %s and user %s by OS.\n', TaskOutFileName(1:end-4), Username );
                                                obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[JobName(1:end-4) '_eTimeProcessUnit.mat']), TempDir, SuccessMsg);
                                                save( fullfile(obj.JobManagerParam.TempJMDir,'eTimeProcessUnit.mat'), 'eTimeProcessUnit', 'NodeID_Times' );
                                            end
                                        end
                                        
                                        % Update the current job's ProcessDuration in the global UserUsageInfo structure.
                                        UserAllJobIDs = CurrentUserUsageInfo.UserUsage(1,:);
                                        CurrentUserUsageInfo.UserUsage(4,UserAllJobIDs == JobInfo.JobID) = JobInfo.JobTiming.ProcessDuration;
                                        CurrentUserUsageInfo.TotalProcessDuration = sum( CurrentUserUsageInfo.UserUsage(4,:) );
                                        UserInfoFileUpdated = 1;
                                        
                                        Msg = sprintf( '\n\n\nConsolidating finished tasks associated with job %s for user %s is DONE at %s!\n\n\n',...
                                            JobName, Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                        PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                                        
                                        if( ~isempty(JobDirectory) && strcmpi(JobDirectory,JobRunningDir) ) % The job is loaded from JobRunning directory.
                                            % Determine if the global stopping criteria have been reached/met. Moreover, determine and echo progress of running JobName.
                                            % Furthermore, update Results file.
                                            [StopFlag, JobInfo, JobParam, JobState] = obj.DetermineStopFlag(JobParam, JobState, JobInfo, JobName, Username, FiguresDir);
                                            
                                            if ~StopFlag    % If simulation of the job JobName is NOT done, resubmit another round of tasks.
                                                % Save the result in JobRunning queue/directory.
                                                try
                                                    save( fullfile(JobRunningDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                    SuccessMsg = sprintf( 'The corresponding job file %s of user %s is updated in the JobRunning directory.\n', JobName(1:end-4), Username );
                                                    PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                                                catch
                                                    save( fullfile(obj.JobManagerParam.TempJMDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                    obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,JobName), JobRunningDir);
                                                    SuccessMsg = sprintf( 'The corresponding job file %s of user %s is updated in the JobRunning directory by OS.\n', JobName(1:end-4), Username );
                                                    PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                                                end
                                                
                                                TimeFromFirstTaskGenRound =  etime(clock, datevec(JobInfo.JobTiming.StartTime,'ddd., mmm dd, yyyy HH:MM:SS PM'));
                                                if( TimeFromFirstTaskGenRound > 1.2*CurrentUser.InitialRunTime )
                                                    
                                                    % Limit the simulation maximum runtime of each task.
                                                    if( isfield(JobParam, 'MaxRunTime') && (JobParam.MaxRunTime ~= -1) )
                                                        TaskMaxRunTime = JobParam.MaxRunTime;
                                                    else
                                                        TaskMaxRunTime = CurrentUser.MaxRunTime;
                                                    end
                                                    
                                                    % Determine the number of new tasks to be generated for the current user.
                                                    NumNewTasks = obj.FindNumNewTasks(CurrentUser);
                                                    
                                                    if NumNewTasks > 0
                                                        % Divide the JOB into multiple TASKs.
                                                        [CurrentUser.TaskID, JobState] = obj.DivideJob2Tasks(JobParam, JobState, CurrentUser, NumNewTasks, JobName, TaskMaxRunTime);
                                                        
                                                        if( isfield(JobState, 'JobFileUpdateRequest') && ~isempty(JobState.JobFileUpdateRequest) &&...
                                                                JobState.JobFileUpdateRequest == 1 )
                                                            JobState = rmfield(JobState, {'JobFileUpdateRequest'});
                                                            % Update the copy of the selected job in the JobRunning directory. The JobState has been updated.
                                                            try
                                                                save( fullfile(JobRunningDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                                % SuccessMsg = sprintf( 'Running job file %s of user %s is UPDATED in its JobRunning directory.\n', JobName(1:end-4), Username );
                                                                % PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                                                            catch
                                                                save( fullfile(obj.JobManagerParam.TempJMDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                                % SuccessMsg = sprintf( 'Running job file %s of user %s is UPDATED in its JobRunning directory by OS.\n', JobName(1:end-4), Username );
                                                                SuccessMsg = [];
                                                                TempvgFlag = obj.JobManagerParam.vqFlag;
                                                                obj.JobManagerParam.vqFlag = 0;
                                                                obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,JobName), JobRunningDir, SuccessMsg);
                                                                obj.JobManagerParam.vqFlag = TempvgFlag;
                                                            end
                                                        end
                                                        
                                                    end
                                                end
                                            else % If simulation of this job is done, save the result in JobOut queue/directory.
                                                StopTime = datenum(clock);
                                                % Set the job StopTime.
                                                JobInfo = obj.UpdateJobInfo(JobInfo, 'StopTime', StopTime, 'Status', 'Done');
                                                
                                                % Set the job StopTime in the global UserUsageInfo structure.
                                                UserAllJobIDs = CurrentUserUsageInfo.UserUsage(1,:);
                                                CurrentUserUsageInfo.UserUsage(3,UserAllJobIDs == JobInfo.JobID) = StopTime;
                                                
                                                % More Cleanup Needed: Any tasks associated with this job should be deleted from TaskIn directory.
                                                if ~isempty( dir( fullfile(TaskInDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']) ) )
                                                    obj.DeleteFile( fullfile(TaskInDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']) );
                                                end
                                                
                                                try
                                                    save( fullfile(JobOutDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                    SuccessMsg = sprintf( 'The FINISHED job file %s of user %s is moved to JobOut directory.\n', JobName(1:end-4), Username );
                                                    PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                                                catch
                                                    save( fullfile(obj.JobManagerParam.TempJMDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                                    obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,JobName), JobOutDir);
                                                    SuccessMsg = sprintf( 'The FINISHED job file %s of user %s is moved to JobOut directory by OS.\n', JobName(1:end-4), Username );
                                                    PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                                                end
                                                % Move all pdf files containing figures to JobOut directory.
                                                % if ~isempty( dir(fullfile(FiguresDir,[JobName(1:end-4) '*.pdf'])) )
                                                %     obj.MoveFile(fullfile(FiguresDir,[JobName(1:end-4) '*.pdf']), JobOutDir);
                                                % end
                                                
                                                % Delete all pdf files containing figures from Figures directory.
                                                % obj.DeleteFile( fullfile(FiguresDir,[JobName(1:end-4) '*.pdf']) );
                                                
                                                % ChmodStr = ['chmod 666 ' FileName];   % Allow everyone to read and write to the file, FileName.
                                                % system( ChmodStr );
                                                
                                                % Remove the finished job from JobRunning queue/directory.
                                                obj.DeleteFile( fullfile(JobRunningDir,JobName) );
                                                % msgStatus = sprintf( 'Done' );
                                                % SuccessFlagStatus = obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Status.txt'], msgStatus, 'w+');
                                                % obj.UpdateResultsStatusFile(JobRunningDir, [JobName(1:end-4) '_Status.txt'], msgStatus, 'w+');
                                                % obj.DeleteFile( fullfile(JobRunningDir,[JobName(1:end-4) '_Results.txt']) );
                                                % obj.DeleteFile( fullfile(JobRunningDir,[JobName(1:end-4) '_Status.txt']) );
                                            end
                                            
                                        elseif( ~isempty(JobDirectory) && strcmpi(JobDirectory,JobOutDir) ) % The job is loaded from JobOut directory.
                                            % Cleanup: Any tasks associated with this job should be deleted from TaskIn directory.
                                            if ~isempty( dir(fullfile(TaskInDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat'])) )
                                                obj.DeleteFile( fullfile(TaskInDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']) );
                                            end
                                            
                                            % Save the updated final result for the job in JobOut directory.
                                            try
                                                save( fullfile(JobOutDir,JobName), 'JobParam', 'JobState', 'JobInfo' );
                                            catch
                                                save( fullfile(obj.JobManagerParam.TempJMDir,JobName), 'JobParam', 'JobState', 'JobInfo'  );
                                                obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,JobName), JobOutDir);
                                            end
                                        end
                                    end
                                    
                                    end
                                    end
                                end
                                
                                Msg = sprintf( '\n\n\nSweeping JobIn, JobRunning, and TaskOut directories of user %s is finished at %s.\n\n\n',...
                                    Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                                PrintOut(Msg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                                
                                CurrentUserUsageInfo.TaskID = CurrentUser.TaskID;
                                CurrentUser = rmfield(CurrentUser, 'TaskID');
                                obj.UserList(User) = CurrentUser;
                                obj.JobManagerInfo.UserUsageInfo(CurrentUserInfoFlag==1) = CurrentUserUsageInfo;
                            end
                            
                            % Wait briefly before looping for the next active user.
                            pause( CurrentUser.PauseTime );
                        end
                        
                        % Update the file containing user usage information.
                        if UserInfoFileUpdated == 1
                            obj.CreateUsageFile(obj.JobManagerInfo.UserUsageInfo);
                        end
                        
                        
                        if rem(Check4NewUser, obj.JobManagerParam.JMInfoUpdatePeriod)==0
                            JobManagerParam = obj.JobManagerParam;
                            JobManagerInfo = obj.JobManagerInfo;
                            UserList = obj.UserList;
                            try
                                save( obj.JobManagerParam.JMInfoFullPath, 'JobManagerParam', 'JobManagerInfo', 'UserList' );
                                SuccessMsg = sprintf( '\nJob manager parameters and information containing the user list and user usage information is saved.\n\n' );
                                PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                            catch
                                [JMInfoPath, JMInfoName, JMInfoExt] = fileparts(obj.JobManagerParam.JMInfoFullPath);
                                save( fullfile(obj.JobManagerParam.TempJMDir,[JMInfoName, JMInfoExt]), 'JobManagerParam', 'JobManagerInfo', 'UserList' );
                                obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[JMInfoName, JMInfoExt]), JMInfoPath);
                                SuccessMsg = sprintf( '\nJob manager parameters and information containing the user list and user usage information is saved by OS.\n\n' );
                                PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
                            end
                        end
                        
                        if(Check4NewUser >= obj.JobManagerParam.Check4NewUserPeriod), break; end
                    end
                else % If there is no ACTIVE user in the system, pause briefly before looking for new users again.
                    pause(obj.JobManagerParam.JMPause);
                end
            end
        end
        
        
        function JobManagerParam = InitJobManager(obj, cfgFullFile, JmName)
            % Initialize job manager's parameters in JobManagerParam structure.
            %
            % Calling syntax: JobManagerParam = obj.InitJobManager([cfgFullFile])
            % Optional input cfgFullFile is the FULL path to the configuration file of the job manager.
            % JobManagerParam fields:
            %       ProjectName,HomeRoot,TempJMDir,JMInfoFullPath,JMInfoUpdatePeriod,Check4NewUserPeriod,JMPause,
            %       UserCfgFilename,LogFileName,vqFlag,MaxRecentTaskInfo.
            %
            % Version 1, 02/07/2011, Terry Ferrett.
            % Version 2, 01/11/2012, Mohammad Fanaei.
            % Version 3, 02/13/2012, Mohammad Fanaei.
            
            % Named constants.
            JobManagerParam = struct;
            JobManagerParam.JmName = JmName;
            
            if( nargin<2 || isempty(cfgFullFile) )
                JobManagerParam.ProjectName = input(['\nWhat is the name of the current project for which this Job Manager is running?\n',...
                    'This will be used to locate the configuration file of this Job Manager.\n\n'],'s');
                if ispc
                    cfgRoot = input('\nWhat is the FULL path to the FOLDER in which the CONFIGURATION file of this Job Manager is located?\n\n','s');
                else
                    cfgRoot = fullfile(filesep,'home','pcs','jm',JobManagerParam.ProjectName,'cfg');
                end
                CFG_Filename = input('\nWhat is the name of the CONFIGURATION file for this Job Manager?\nExample: <ProjectName>JobManager_cfg\n\n','s');
                % Find CFG_Filename file, i.e., job manager's configuration file.
                cfgFullFile = fullfile(cfgRoot, CFG_Filename);
            end
            
            cfgFileDir = dir(cfgFullFile);
            
            if( ~isempty(cfgFileDir) )
                heading1 = '[GeneralSpec]';
                
                % Read the name of the current project for which this job manager is running.
                out = util.fp(cfgFullFile, heading1, 'ProjectName'); out = out{1}{1};
                if( isempty(out) && (~isfield(JobManagerParam,'ProjectName') || isempty(JobManagerParam.ProjectName)) )
                    JobManagerParam.ProjectName = input('\nWhat is the name of the current project for which this Job Manager is running?\n\n','s');
                elseif( ~isempty(out) )
                    JobManagerParam.ProjectName = out;
                end
                
                % Read root directory in which the job manager looks for users of the system.
                out = util.fp(cfgFullFile, heading1, 'HomeRoot');
                if isempty(out)
                    if ispc, outChar = input('\nWhat is the FULL path to the HOME ROOT in which the Job Manager should look for system USERS?\n\n','s');
                    else outChar = [filesep 'home'];
                    end
                else
                    for DirNum = 1:length(out)
                        outChar{DirNum} = out{DirNum}{1};
                    end
                end
                JobManagerParam.HomeRoot = outChar;
                
                % Read temporary directory in which the job manager saves intermediate files before moving them to their ultimate destination.
                % This folder solves the problem of write permissions in directories of users.
                out = util.fp(cfgFullFile, heading1, 'TempJMDir'); out = out{1}{1};
                if isempty(out)
                    if ispc
                        out = input(['\nWhat is the FULL path to the TEMPORARY folder (TempJMDir) in which the Job Manager saves intermediate files\n',...
                            'before moving them to their ultimate destinations?\n\n'],'s');
                    else
                        out = fullfile('home','pcs','jm',JobManagerParam.ProjectName,'Temp');
                    end
                end
                JobManagerParam.TempJMDir = out;
                
                % Read FULL path (including name) of .mat file containing job manager Info and Usage (including timing and credit usage info of users).
                out = util.fp(cfgFullFile, heading1, 'JMInfoFullPath'); out = out{1}{1};
                if isempty(out)
                    if ispc, out = input('\nWhat is the FULL path to the .mat file containing Job Manager Info and Usage (including TIMING and CREDIT USAGE Info of users)?\n\n','s');
                    else out = fullfile(filesep,'home','pcs','jm',JobManagerParam.ProjectName,'Usage',[JobManagerParam.ProjectName '_jmUsageInfo.mat']);
                    end
                end
                JobManagerParam.JMInfoFullPath = out;
                
                % Read period by which the job manager parameters and information containing the user list and user usage information is saved.
                out = util.fp(cfgFullFile, heading1, 'JMInfoUpdatePeriod'); out = out{1}{1};
                if( isempty(out) ), out = '10'; end
                JobManagerParam.JMInfoUpdatePeriod = str2double(out);
                
                % Read period by which the job manager looks for newly-added users to the system.
                out = util.fp(cfgFullFile, heading1, 'Check4NewUserPeriod'); out = out{1}{1};
                if( isempty(out) ), out = '50'; end
                JobManagerParam.Check4NewUserPeriod = str2double(out);
                
                % Read job manager's pause time to wait before looking for new users when there is no active user in the system.
                out = util.fp(cfgFullFile, heading1, 'JMPause'); out = out{1}{1};
                if( isempty(out) ), out = '60'; end
                JobManagerParam.JMPause = str2double(out);
                
                % Read name of configuration file for each user, which stores location of JOB queues for each project (among other information).
                out = util.fp(cfgFullFile, heading1, 'UserCfgFilename'); out = out{1}{1};
                if( isempty(out) )
                    out = input(['\nWhat is the name of CONFIGURATION file for USERs?\n%',...
                        'The job manager looks for this file in the users home directories to find active users.\nExam%ple: <ProjectName>_cfg\n\n'],'s');
                end
                JobManagerParam.UserCfgFilename = out;
                
                
                heading2 = '[LogSpec]';
                
                % Read job manager's log filename.
                out = util.fp(cfgFullFile, heading2, 'LogFileName'); out = out{1}{1};
                if( isempty(out) ), out = '0'; end
                if strcmp(out, '0'), out = str2double(out); end
                JobManagerParam.LogFileName = out;
                
                % Read verbose/quiet mode of intermediate message logging.
                % If vqFlag=0 (verbose mode), all detailed intermediate messages are printed out.
                % If vqFlag=1 (quiet mode), just important intermediate messages are printed out.
                out = util.fp(cfgFullFile, heading2, 'vqFlag'); out = out{1}{1};
                if( isempty(out) ), out = '0'; end
                JobManagerParam.vqFlag = str2double(out);
                
                
                heading3 = '[eTimeProcessUnitSpec]';
                
                % Read maximum number of recent trial numbers and processing times of each worker node saved for billing purposes.
                out = util.fp(cfgFullFile, heading3, 'MaxRecentTaskInfo'); out = out{1}{1};
                if( isempty(out) ), out = '5'; end
                JobManagerParam.MaxRecentTaskInfo = str2double(out);
                
            else
                if( ~isfield(JobManagerParam,'ProjectName') || isempty(JobManagerParam.ProjectName) )
                    JobManagerParam.ProjectName = input('\nWhat is the name of the current project for which this Job Manager is running?\n\n','s');
                end
                
                if ispc, JobManagerParam.HomeRoot = input('\nWhat is the FULL path to the HOME ROOT in which the Job Manager should look for system USERS?\n\n','s');
                else JobManagerParam.HomeRoot = [filesep 'home'];
                end
                
                if ispc
                    JobManagerParam.TempJMDir = input(['\nWhat is the FULL path to the TEMPORARY folder (TempJMDir) in which the Job Manager saves\n',...
                        'intermediate files before moving them to their ultimate destinations?\n\n'],'s');
                else
                    JobManagerParam.TempJMDir = fullfile(JobManagerParam.HomeRoot,'pcs','jm',JobManagerParam.ProjectName,'Temp');
                end
                
                if ispc
                    JobManagerParam.JMInfoFullPath = input(['\nWhat is the FULL path to the .mat file containing Job Manager Info and Usage',...
                        '(including TIMING and CREDIT USAGE Info of users)?\n\n'],'s');
                else
                    JobManagerParam.JMInfoFullPath = fullfile(filesep,'home','pcs','jm',JobManagerParam.ProjectName,'Usage',[JobManagerParam.ProjectName '_jmInfo.mat']);
                end
                JobManagerParam.JMInfoUpdatePeriod = 10;
                JobManagerParam.Check4NewUserPeriod = 50;
                JobManagerParam.JMPause = 60;
                
                JobManagerParam.UserCfgFilename = input(['\nWhat is the name of CONFIGURATION file for USERs?\n%',...
                    'The job manager looks for this file in the users home directories to find active users.\nExam%ple: <ProjectName>_cfg\n\n'],'s');
                
                JobManagerParam.LogFileName = 0;
                % if ispc
                %     JobManagerParam.LogFileName = input('\nWhat is the FULL path (including File Name) to the LOG file for this Job Manager?\n\n','s');
                % else
                %     LogFileName = input('\nWhat is the name of the LOG file for this Job Manager?\n\n','s');
                %     JobManagerParam.LogFileName = fullfile(filesep,'rhome','pcs','jm',JobManagerParam.ProjectName,'log',LogFileName);
                % end
                
                JobManagerParam.vqFlag = 0;
                JobManagerParam.MaxRecentTaskInfo = 5;
            end
        end
        
        
        function JobManagerInfo = InitJobManagerInfo(obj)
            
            if( exist(obj.JobManagerParam.JMInfoFullPath, 'file') ~= 0 )
                load(obj.JobManagerParam.JMInfoFullPath, 'JobManagerInfo');
            else
                JobManagerInfo = struct('JobID', 0, 'UserUsageInfo', []);
                JobManagerParam = obj.JobManagerParam;
                UserList = [];
                try
                    save(obj.JobManagerParam.JMInfoFullPath, 'JobManagerParam', 'JobManagerInfo', 'UserList');
                catch
                    [FileInfoPath, FileInfoName, FileInfoExt] = fileparts(obj.JobManagerParam.JMInfoFullPath);
                    if( isempty(FileInfoExt) ), FileInfoExt = '.mat'; end
                    save( fullfile(obj.JobManagerParam.TempJMDir,[FileInfoName FileInfoExt]), 'JobManagerParam', 'JobManagerInfo', 'UserList' );
                    obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[FileInfoName FileInfoExt]), obj.JobManagerParam.JMInfoFullPath);
                end
            end
            
        end
        
        
        function [UserList, UserUsageInfo] = InitUsers(obj)
            % Initialize users' states in UserList and UserUsageInfo structures.
            %
            % Calling syntax: [UserList, UserUsageInfo] = obj.InitUsers()
            % UserList fields for EACH user:
            %       UserPath(Full Path),CodeRoot,JobQueueRoot,(TasksRoot),TaskInDir,TaskOutDir,FunctionName,FunctionPath,MaxInputTasks,
            %       TaskGenDecelerate,MaxTaskGenStep,TaskInFlushRate,MaxRunningJobs,InitialRunTime,MaxRunTime,PauseTime.
            % UserUsageInfo fields for EACH user:
            %       Username,TaskID,UserUsage=[JobID;JobStartTime;JobStopTime;JobProcessDuration],TotalProcessDuration.
            %
            % Version 1, 02/07/2011, Terry Ferrett.
            % Version 2, 10/01/2012, Mohammad Fanaei.
            
            % Named constants.
            HomeRoot = obj.JobManagerParam.HomeRoot;
            if( ~isfield(obj.JobManagerParam,'UserCfgFilename') || isempty(obj.JobManagerParam.UserCfgFilename) )
                obj.JobManagerParam.UserCfgFilename = input(['\nWhat is the name of CONFIGURATION file for USERs?\n',...
                    'The job manager looks for this file in the users home directories to find active users.\nExample: <ProjectName>_cfg\n\n'],'s');
            end
            CFG_Filename = obj.JobManagerParam.UserCfgFilename;
            
            % Perform a directory listing in HomeRoot to list ALL possible users.
            UserDirs = [];
            if iscell(HomeRoot)
                RootInd = [];
                for ll = 1:length(HomeRoot)
                    UserDirs = [UserDirs ; dir(HomeRoot{ll})];
                    RootInd = [RootInd ; ll*ones(size(dir(HomeRoot{ll})))];
                end
            else
                UserDirs = dir(HomeRoot);
            end
            
            UserList = obj.UserList;
            UserUsageInfo = obj.JobManagerInfo.UserUsageInfo;
            n = length(UserDirs);        % Number of directories found in HomeRoot.
            UserCount = length(UserList);% Counter to track number of ACTIVE users.
            % Counter to track TOTAL number of users in the system from the BEGINNING of running job manager.
            TotalUserCount = length(UserUsageInfo);
            
            for k = 1:n
                % Find CFG_Filename file, i.e., project configuration file of each user.
                if iscell(HomeRoot)
                    UserPath = fullfile(HomeRoot{RootInd(k)}, UserDirs(k).name);
                else
                    UserPath = fullfile(HomeRoot, UserDirs(k).name);
                end
                cfgFile = fullfile(UserPath, CFG_Filename);
                cfgFileDir = dir(cfgFile);
                
                UserFoundFlag = zeros(UserCount,1);
                for u = 1:UserCount
                    UserFoundFlag(u) = strcmpi( UserList(u).UserPath, UserPath );
                end
                
                % If CFG_Filename (project configuration file) exists AND {EITHER user is NOT already listed in UserList OR
                % CFG_Filename is modified since the last time it is read}, read CFG_Filename.
                if( ~isempty(cfgFileDir) && ( sum(UserFoundFlag)==0 || datenum( UserList(UserFoundFlag==1).CfgFileModDate ) < UserDirs(k).datenum ) )
                    if( sum(UserFoundFlag)~=0 )
                        if datenum( UserList(UserFoundFlag==1).CfgFileModDate ) < UserDirs(k).datenum
                            UserList(UserFoundFlag==1) = [];
                        end
                    end
                    if sum(UserFoundFlag)==0
                        UserCount = UserCount + 1;
                    end
                    
                    % Add FULL path to this user to active users list.
                    UserList(UserCount).UserPath = UserPath;
                    
                    heading1 = '[GeneralSpec]';
                    
                    % Read name and FuLL path to user's actual CODE directory.
                    % All of the code required to run user's simulations resides under this directory.
                    out = util.fp(cfgFile, heading1, 'CodeRoot'); out = out{1}{1};
                    UserList(UserCount).CodeRoot = out;
                    
                    % Read name and FULL path to user's job queue root directory. JobIn, JobRunning, and JobOut directories are under this full path.
                    out = util.fp(cfgFile, heading1, 'JobQueueRoot'); out = out{1}{1};
                    % out = cell2mat([out{:}]);
                    if isempty(out)
                        out = fullfile(UserPath,'Projects',obj.JobManagerParam.ProjectName);
                        % else
                        % This line was commented on 08/01/2012 since this field was modified in the configuration file to not have ' at its beginning and end.
                        %     out = eval(out);
                    end
                    UserList(UserCount).JobQueueRoot = out;
                    
                    % Read name and FULL path to user's task directory. TaskIn and TaskOut directories are under this path.
                    % out = util.fp(cfgFile, heading1, 'TasksRoot'); out = out{1}{1};
                    % out = cell2mat([out{:}]);
                    % if isempty(out)
                    %     out = fullfile(UserPath,'Tasks');
                    % else
                    %     out = eval(out);
                    % end
                    % UserList(UserCount).TasksRoot = out;
                    
                    % Read TaskCfgFileName from queue configuration file.
                    headingT = '[cfg]';
                    key = 'user';
                    out = util.fp(obj.JobManagerParam.queueCfg, headingT, key);
                    TaskCfgFileName = out{1}{1};
                    
                    % TaskCfgFileName = 'ctc_cfg';
                    out = util.fp( fullfile(UserPath,TaskCfgFileName), '[paths]', 'input' ); out = out{1}{1};
                    UserList(UserCount).TaskInDir = out;
                    out = util.fp( fullfile(UserPath,TaskCfgFileName), '[paths]', 'output' ); out = out{1}{1};
                    UserList(UserCount).TaskOutDir = out;
                    
                    % Read name and full path of function to be executed for running each task.
                    out = util.fp(cfgFile, heading1, 'FunctionName'); out = out{1}{1};
                    UserList(UserCount).FunctionName = out;
                    
                    out = util.fp(cfgFile, heading1, 'FunctionPath'); out = out{1}{1};
                    UserList(UserCount).FunctionPath = out;
                    
                    UserList(UserCount).CfgFileModDate = UserDirs(k).date;
                    
                    
                    heading2 = '[TasksInSpec]';
                    
                    % Read maximum number of input tasks in TaskIn queue/directory.
                    out = util.fp(cfgFile, heading2, 'MaxInputTasks'); out = out{1}{1};
                    if( isempty(out) ), out = '1000'; end
                    UserList(UserCount).MaxInputTasks = str2double(out);
                    
                    % Read the number of input tasks in TaskIn queue/directory beyond which generation of new tasks is slowed down until it reaches the maximum of MaxInputTasks.
                    out = util.fp(cfgFile, heading2, 'TaskGenDecelerate'); out = out{1}{1};
                    if( isempty(out) ), out = '750'; end
                    UserList(UserCount).TaskGenDecelerate = str2double(out);
                    
                    % Read maximum number of input tasks to be submitted to TaskIn at a time/each step.
                    out = util.fp(cfgFile, heading2, 'MaxTaskGenStep'); out = out{1}{1};
                    if( isempty(out) ), out = '60'; end
                    UserList(UserCount).MaxTaskGenStep = str2double(out);
                    
                    % Read number of new input tasks saved in temporary directory (TempJMDir) that should be moved to TaskIn directory of user at a time.
                    out = util.fp(cfgFile, heading2, 'TaskInFlushRate'); out = out{1}{1};
                    if( isempty(out) ), out = '10'; end
                    UserList(UserCount).TaskInFlushRate = str2double(out);
                    
                    % Read maximum number of parallel jobs running at a time.
                    out = util.fp(cfgFile, heading2, 'MaxRunningJobs'); out = out{1}{1};
                    if( isempty(out) ), out = '3'; end
                    UserList(UserCount).MaxRunningJobs = str2double(out);
                    
                    
                    heading3 = '[RunTimeSpec]';
                    
                    % Read quick initial running time of each task to quickly get initial results back.
                    out = util.fp(cfgFile, heading3, 'InitialRunTime'); out = out{1}{1};
                    if( isempty(out) ), out = '60'; end
                    UserList(UserCount).InitialRunTime = str2double(out);
                    
                    % Read longer running time of each task in the long term.
                    out = util.fp(cfgFile, heading3, 'MaxRunTime'); out = out{1}{1};
                    if( isempty(out) ), out = '300'; end
                    UserList(UserCount).MaxRunTime = str2double(out);
                    
                    % Read pause time to wait between task submissions and flow control.
                    out = util.fp(cfgFile, heading3, 'PauseTime'); out = out{1}{1};
                    if( isempty(out) ), out = '0.1'; end
                    UserList(UserCount).PauseTime = str2double(out);
                    
                    % Initialize UserUsageInfo entry for the added user IF the user is NOT already listed.
                    if sum(UserFoundFlag)==0
                        UserInfoFoundFlag = zeros(TotalUserCount,1);
                        for v = 1:TotalUserCount
                            UserInfoFoundFlag(v) = strcmpi( UserUsageInfo(v).Username, UserDirs(k).name );
                        end
                        
                        if( sum(UserInfoFoundFlag)==0 )
                            TotalUserCount = TotalUserCount + 1;
                            UserUsageInfo(TotalUserCount).Username = UserDirs(k).name;
                            % Reset the task ID counter.
                            UserUsageInfo(TotalUserCount).TaskID = 0;
                            UserUsageInfo(TotalUserCount).UserUsage = zeros(4,1);
                            UserUsageInfo(TotalUserCount).TotalProcessDuration = 0;
                        end
                    end
                    
                    % If user is already listed in UserList but its CFG_Filename (project configuration file) does not exist anymore, remove user from list.
                elseif( (sum(UserFoundFlag)~=0) && isempty(cfgFileDir) )
                    UserList(UserFoundFlag == 1) = [];
                    UserCount = UserCount - sum(UserFoundFlag);
                end
            end
        end
        
        
        function JobInfo = InitJobInfo(obj)
            
            JobTiming = struct('StartTime', [], ...
                'StopTime', [], ...
                'ProcessDuration', 0);
            
            JobError = struct('ErrorType', [], 'ErrorMsg', []);
            
            JobWarning = struct('WarningType', [], 'WarningMsg', []);
            
            JobInfo = struct('JobID', [], ...
                'JobTiming', JobTiming, ...
                'Status', [], ...
                'Results', [], ...
                'JobError', JobError, ...
                'JobWarning', JobWarning);
        end
        
        
        function JobInfo = UpdateJobInfo(obj, JobInfo, varargin)
            
            ValidVarNames = {'JobID', 'StartTime', 'StopTime', 'ProcessDuration', 'SpeedProfile', 'Status', 'Results',...
                'ErrorType', 'ErrorMsg', 'WarningType', 'WarningMsg'};
            
            nInArgs = length(varargin);
            if rem(nInArgs,2) ~= 0
                error('UpdateJobInfo:NotNameValuePairs','Inputs of method UpdateJobInfo must be specified in Name/Value pair format!');
            end
            
            VarNames = varargin(1:2:nInArgs);
            VarValues = varargin(2:2:nInArgs);
            
            for Pair = 1:length(VarNames)
                ParamName = VarNames{Pair};
                if any( strcmpi( ParamName, ValidVarNames ) )
                    switch ParamName
                        case {'StartTime', 'StopTime'}
                            JobInfo.JobTiming.(ParamName) = datestr(VarValues{Pair}, 'ddd., mmm dd, yyyy HH:MM:SS PM');
                        case 'SpeedProfile'
                            JobInfo.JobTiming.(ParamName) = VarValues{Pair};
                        case 'ProcessDuration'
                            JobInfo.JobTiming.ProcessDuration = JobInfo.JobTiming.ProcessDuration + VarValues{Pair};
                        case {'ErrorType', 'ErrorMsg'}
                            JobInfo.JobError.(ParamName) = VarValues{Pair};
                        case {'WarningType', 'WarningMsg'}
                            JobInfo.JobWarning.(ParamName) = VarValues{Pair};
                        otherwise % For JobID, Status, and Results.
                            JobInfo.(ParamName) = VarValues{Pair};
                    end
                else
                    error('UpdateJobInfo:InvalidParamName','%s is not a valid recognized input parameter name for method UpdateJobInfo!',ParamName);
                end
            end
            
        end
        
        
        function [JobDirectory, JobNameCell] = SelectInRunningJob(obj, JobInDir, JobRunningDir, MaxRunningJobs, SuccessMsgIn, SuccessMsgRunning, NoJobMsg)
            % Pick a job from JobIn or JobRunning directory and return its directory and its name.
            %
            % Calling syntax: [JobDirectory, JobNameCell] = obj.SelectInRunningJob(JobInDir, JobRunningDir, MaxRunningJobs [,SuccessMsgIn] [,SuccessMsgRunning] [,NoJobMsg])
            % MaxRunningJobs is a POSITIVE maximum number of simultaneously-running jobs.
            DIn = dir( fullfile(JobInDir,'*.mat') );
            DRunning = dir( fullfile(JobRunningDir,'*.mat') );
            
            if( length(DRunning) >= MaxRunningJobs )
                % Pick a running job AT RANDOM.
                JobDirectory = JobRunningDir;
                JobFileIndex = randi( [1 length(DRunning)], [1 1] );
                % Construct the filename.
                JobName = DRunning(JobFileIndex).name;
                if( nargin>=6 && ~isempty(SuccessMsgRunning) )
                    Msg = [SuccessMsgRunning sprintf('Selected JOB name: %s.\n', JobName(1:end-4))];
                    PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                end
                JobNameCell{1} = JobName;
            else
                if ~isempty(DIn)
                    % Pick the OLDEST new job.
                    JobDirectory = JobInDir;
                    [Dummy, DateIndx] = sort( [DIn(:).datenum], 'ascend' );
                    JobFileIndex = DateIndx(1);
                    % Construct the filename.
                    JobName = DIn(JobFileIndex).name;
                    if( nargin>=5 && ~isempty(SuccessMsgIn) )
                        Msg = [SuccessMsgIn sprintf('Selected JOB name: %s.\n', JobName(1:end-4))];
                        PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                    end
                    JobNameCell{1} = JobName;
                elseif ~isempty(DRunning)
                    % Pick a running job AT RANDOM.
                    JobDirectory = JobRunningDir;
                    JobFileIndex = randi( [1 length(DRunning)], [1 1] );
                    % Construct the filename.
                    JobName = DRunning(JobFileIndex).name;
                    if( nargin>=6 && ~isempty(SuccessMsgRunning) )
                        Msg = [SuccessMsgRunning sprintf('Selected JOB name: %s.\n', JobName(1:end-4))];
                        PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                    end
                    JobNameCell{1} = JobName;
                else
                    JobDirectory = [];
                    JobNameCell = {};
                    if( nargin>=7 && ~isempty(NoJobMsg) )
                        PrintOut(NoJobMsg, 0, obj.JobManagerParam.LogFileName);
                    end
                end
            end
        end
        
        
        function JobDirectory = FindRunningOutJob(obj, JobRunningDir, JobOutDir, JobName, ErrorMsg)
            % Calling syntax: JobDirectory = obj.FindRunningOutJob(JobRunningDir, JobOutDir, JobName [,ErrorMsg])
            
            DRunning = dir( fullfile(JobRunningDir,JobName) );
            DOut = dir( fullfile(JobOutDir,JobName) );
            
            if ~isempty(DRunning)
                JobDirectory = JobRunningDir;
            elseif ~isempty(DOut)
                JobDirectory = JobOutDir;
            else
                JobDirectory = [];
                if( nargin>=5 && ~isempty(ErrorMsg) )
                    PrintOut(ErrorMsg, 0, obj.JobManagerParam.LogFileName);
                end
            end
        end
        
        
        function [NodeID_Times, eTimeProcessUnit] = ExtractETimeProcessUnit( obj, TaskInfo, CurrentTime, NumProcessUnit )
            % This function is designed for billing purposes.
            % NodeID_Times is a vector structure with two fields:
            % NodeID and NumNodeTaskInfo (how many times that specific node has generated TaskInfo (run simulations)).
            % The length of this structure is equal to the number of active nodes (NumNode).
            %
            % eTimeProcessUnit is a 3-by-MaxRecentTaskInfo-by-NumNode matrix.
            % Its first row contains the time calculated globally from the start of the job manager until receiving curret consumed task from TaskOut directory.
            % Its second row contains elapsed times in current task at the worker and its third row contains the number of trials completed during the eTime at the worker.
            
            if(nargin<4 || isempty(NumProcessUnit)), NumProcessUnit = []; end
            
            MaxRecentTaskInfo = obj.JobManagerParam.MaxRecentTaskInfo;
            NodeID_Times = obj.NodeID_Times;
            eTimeProcessUnit = obj.eTimeProcessUnit;
            
            % Check to see if the NodeID has already been registered in NodeID_Times.
            NumNode = length(NodeID_Times);
            IndT = zeros(NumNode,1);
            for Node = 1:NumNode
                IndT(Node) = strcmpi( num2str(NodeID_Times(Node).NodeID), TaskInfo.HostName );
            end
            
            Ind = find(IndT~=0,1,'first');
            if isempty(Ind) % This is a new NodeID. Add it to the list of NodeID_Times.
                NodeID_Times = [NodeID_Times ; struct('NodeID',TaskInfo.HostName, 'NumNodeTaskInfo',1)];
                Ind = length(NodeID_Times);
                eTimeProcessUnit = cat(3,eTimeProcessUnit,zeros(3,MaxRecentTaskInfo));
            else            % This NodeID has already been registered in NodeID_Times.
                NodeID_Times(Ind).NumNodeTaskInfo = NodeID_Times(Ind).NumNodeTaskInfo + 1;
            end
            
            if NodeID_Times(Ind).NumNodeTaskInfo <= MaxRecentTaskInfo
                ColPos = NodeID_Times(Ind).NumNodeTaskInfo;
            else
                % Note that the first row of eTimeProcessUnit is cumulative time from the start of the job manager.
                eTimeProcessUnit(2:end,2,:) = eTimeProcessUnit(2:end,1,:) + eTimeProcessUnit(2:end,2,:);
                eTimeProcessUnit = circshift(eTimeProcessUnit, [0 -1 0]);
                ColPos = size(eTimeProcessUnit,2);
            end
            
            % eTimeProcessUnit(:,ColPos,Ind) = [CurrentTime
            %     etime(TaskInfo.StopTime, TaskInfo.StartTime)
            %     sum(TaskInfo.Trials(end,:))];
            eTimeProcessUnit(1:2,ColPos,Ind) = [CurrentTime
                etime(TaskInfo.StopTime, TaskInfo.StartTime)];
            
            if ~isempty(NumProcessUnit)
                eTimeProcessUnit(3,ColPos,Ind) = NumProcessUnit;
            end
            
            obj.NodeID_Times = NodeID_Times;
            obj.eTimeProcessUnit = eTimeProcessUnit;
            
            eTimeProcessUnit( :,all(all(eTimeProcessUnit==0,1),3),: ) = [];
        end
        
        
        function SpeedProfile = FindSpeedProfileInfo(obj, eTimeProcessUnit)
            NumNodes = size(eTimeProcessUnit,3);
            NodeInfo = struct('ActualETime',[],'ProcessDuration',[],'NumProcessUnit',[]);
            NodeInfo = repmat(NodeInfo,NumNodes,1);
            
            for Node = 1:NumNodes
                CurrentNodeInfo = eTimeProcessUnit(:,:,Node);
                CurrentNodeInfo( :,all(CurrentNodeInfo==0,1) ) = [];
                NodeInfo(Node).ActualETime = CurrentNodeInfo(1,:);
                NodeInfo(Node).ProcessDuration = CurrentNodeInfo(2,:);
                NodeInfo(Node).NumProcessUnit = CurrentNodeInfo(3,:);
            end
            
            GlobalInfo = struct('ActualETime',[],'ProcessDuration',[],'NumProcessUnit',[]);
            
            GlobalElapsedTime = [NodeInfo(:).ActualETime];
            GlobalProcessDuration = [NodeInfo(:).ProcessDuration];
            GlobalNumProcessUnit = [NodeInfo(:).NumProcessUnit];
            
            [GlobalInfo.ActualETime, SortOrder] = sort(GlobalElapsedTime);
            GlobalInfo.ProcessDuration = GlobalProcessDuration(SortOrder);
            GlobalInfo.NumProcessUnit = GlobalNumProcessUnit(SortOrder);
            
            SpeedProfile = struct( 'NodeInfo', NodeInfo, 'GlobalInfo', GlobalInfo );
        end
        
        
        function CreateUsageFile(obj, UserUsageInfo)
            UserUsage = struct('Username',[], 'TotalProcessDuration',[]);
            UserUsage = repmat(UserUsage, length(UserUsageInfo), 1);
            
            for User = 1:length(UserUsageInfo)
                UserUsage(User).Username = UserUsageInfo(User).Username;
                UserUsage(User).TotalProcessDuration = num2str( UserUsageInfo(User).TotalProcessDuration );
            end
            
            [JMInfoPath, JMInfoName, JMInfoExt] = fileparts(obj.JobManagerParam.JMInfoFullPath);
            JMUsageName = [obj.JobManagerParam.ProjectName '_Usage'];
            JMUsageExt = '.mat';
            
            try
                save( fullfile(JMInfoPath, [JMUsageName, JMUsageExt]), 'UserUsage' );
                SuccessMsg = sprintf( '\nJob manager user usage information containing the user list and total user usage for this project is saved.\n\n' );
                PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
            catch
                save( fullfile(obj.JobManagerParam.TempJMDir,[JMUsageName, JMUsageExt]), 'UserUsage' );
                obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[JMUsageName, JMUsageExt]), JMInfoPath);
                SuccessMsg = sprintf( '\nJob manager user usage information containing the user list and total user usage for this project is saved by OS.\n\n' );
                PrintOut(SuccessMsg, 0, obj.JobManagerParam.LogFileName);
            end
        end
        
        
        function DeleteFile(obj, FullFileName, SuccessMsg, ErrorMsg)
            % Calling Syntax: obj.DeleteFile(FullFileName [,SuccessMsg] [,ErrorMsg])
            try
                RmStr = ['sudo rm ' FullFileName];
                sysStatus = system( RmStr );
                if sysStatus==0     % Successful deletion of FullFileName.
                    if( (nargin>=3) && ~isempty(SuccessMsg) )
                        PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                    end
                else
                    delete( FullFileName );
                    if( (nargin>=3) && ~isempty(SuccessMsg) )
                        PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                    end
                end
            catch % Unsuccessful deletion of FullFileName.
                if( (nargin>=4) && ~isempty(ErrorMsg) )
                    PrintOut(ErrorMsg, 0, obj.JobManagerParam.LogFileName);
                end
            end
        end
        
        
        function [FileContent, SuccessFlag] = LoadFile(obj, FullFileName, FieldA, FieldB, FieldC, SuccessMsg, ErrorMsg)
            % Calling Syntax: [FileContent, SuccessFlag] = obj.LoadFile(FullFileName, FieldA, FieldB, FieldC [,SuccessMsg] [,ErrorMsg])
            SuccessFlag = 0;
            try
                FileContent = load( FullFileName, FieldA, FieldB, FieldC );
                if( isfield(FileContent,FieldA) && isfield(FileContent,FieldB) && isfield(FileContent,FieldC) )
                    SuccessFlag = 1;
                end
            catch
            end
            if( (SuccessFlag == 1) && nargin>=6 && ~isempty(SuccessMsg) )
                PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
            elseif(SuccessFlag == 0) % FullFileName was bad, kick out of loading loop.
                FileContent = [];
                if( nargin>=7 && ~isempty(ErrorMsg) )
                    PrintOut(ErrorMsg, 0, obj.JobManagerParam.LogFileName);
                end
            end
        end
        
        
        function SuccessFlag = MoveFile(obj, FullFileName, FullDestination, SuccessMsg, ErrorMsg)
            % Calling Syntax: SuccessFlag = obj.MoveFile(FullFileName, FullDestination [,SuccessMsg] [,ErrorMsg])
            [mvStatus,mvMsg] = movefile(FullFileName, FullDestination, 'f');
            if( (mvStatus==1) && isempty(mvMsg) ) % Successful moving of FullFileName to FullDestination.
                SuccessFlag = 1;
                if( nargin>=4 && ~isempty(SuccessMsg) )
                    PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                end
            else % Unsuccessful moving of FullFileName to FullDestination using MATLAB's built-in movefile function.
                MvStr = ['sudo mv ' FullFileName ' ' FullDestination];
                sysStatus = system( MvStr );
                if sysStatus==0 % Successful moving of FullFileName to FullDestination by OS.
                    SuccessFlag = 1;
                    if( nargin>=4 && ~isempty(SuccessMsg) )
                        PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                    end
                else % Unsuccessful moving of FullFileName to FullDestination by both MATLAB and OS.
                    SuccessFlag = 0;
                    if( nargin>=5 && ~isempty(ErrorMsg) )
                        PrintOut(ErrorMsg, 0, obj.JobManagerParam.LogFileName);
                    end
                end
            end
        end
        
        
        function SuccessFlag = CopyFile(obj, FullFileName, FullDestination, SuccessMsg, ErrorMsg)
            % Calling Syntax: SuccessFlag = obj.CopyFile(FullFileName, FullDestination [,SuccessMsg] [,ErrorMsg])
            [cpStatus,cpMsg] = copyfile(FullFileName, FullDestination, 'f');
            if( (cpStatus==1) && isempty(cpMsg) ) % Successful copying of FullFileName to FullDestination.
                SuccessFlag = 1;
                if( nargin>=4 && ~isempty(SuccessMsg) )
                    PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                end
            else % Unsuccessful copying of FullFileName to FullDestination using MATLAB's built-in copyfile function.
                CpStr = ['sudo cp ' FullFileName ' ' FullDestination];
                sysStatus = system( CpStr );
                if sysStatus==0 % Successful copying of FullFileName to FullDestination by OS.
                    SuccessFlag = 1;
                    if( nargin>=4 && ~isempty(SuccessMsg) )
                        PrintOut(SuccessMsg, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                    end
                else % Unsuccessful copying of FullFileName to FullDestination by both MATLAB and OS.
                    SuccessFlag = 0;
                    if( nargin>=5 && ~isempty(ErrorMsg) )
                        PrintOut(ErrorMsg, 0, obj.JobManagerParam.LogFileName);
                    end
                end
            end
        end
        
        
        function SuccessFlag = UpdateResultsStatusFile(obj, FileDestination, FileName, Msg, fopenPerm)
            % Calling syntax: SuccessFlag = obj.UpdateResultsStatusFile(FileDestination, FileName, Msg [,fopenPerm])
            % If fopenPerm = 'w+', it opens or creates FileName for reading and writing. Discard existing contents.
            % If fopenPerm = 'a+', it opens or creates FileName for reading and writing. Append data to the end of FileName.
            if( nargin<5 || isempty(fopenPerm) ), fopenPerm = 'w+'; end
            FileFullPath = fullfile(obj.JobManagerParam.TempJMDir,FileName);
            FID_RSFile = fopen(FileFullPath, fopenPerm);
            fprintf( FID_RSFile, Msg );
            fclose(FID_RSFile);
            % SuccessFlag = obj.MoveFile(FileFullPath, FileDestination, SuccessMsg, ErrorMsg);
            SuccessFlag = obj.MoveFile(FileFullPath, FileDestination);
        end
        
        
        function FinalTaskID = SaveTaskInFiles(obj, TaskInputParam, UserParam, JobName, TaskMaxRunTime)
            % TaskInputParam is NumNewTasks-by-1 vector of structures each one of them associated with one TaskInputParam.
            if( nargin<5 || isempty(TaskMaxRunTime) ), TaskMaxRunTime = UserParam.MaxRunTime; end
            
            % TaskInDir = fullfile(UserParam.TasksRoot,'TaskIn');
            TaskInDir = UserParam.TaskInDir;
            % [HomeRoot, Username, Extension, Version] = fileparts(UserParam.UserPath);
            % [Dummy, Username] = fileparts(UserParam.UserPath);
            Username = obj.FindUsername(UserParam.UserPath);
            OS_flag = 0;
            
            TaskParam = struct(...
                'FunctionName', UserParam.FunctionName,...
                'FunctionPath', UserParam.FunctionPath,...
                'InputParam', []);
            
            % Submit each task one-by-one. Make sure that each task has a unique name.
            for TaskCount=1:length(TaskInputParam)
                % Increment TaskID counter.
                UserParam.TaskID = UserParam.TaskID + 1;
                TaskInputParam(TaskCount).MaxRunTime = TaskMaxRunTime;
                TaskInputParam(TaskCount).RandSeed = mod(UserParam.TaskID*sum(clock), 2^32);
                
                TaskParam.InputParam = TaskInputParam(TaskCount);
                
                % Create the name of the new task, which includes the job name.
                TaskName = [obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_' int2str(UserParam.TaskID) '.mat'];
                
                % Save the new task in TaskIn queue/directory.
                MsgQuiet = '+';
                try
		save('/home/tferrett/HI.mat', 'a');
                    save( fullfile(TaskInDir,TaskName), 'TaskParam' );
                    MsgVerbose = sprintf( 'Task file %s for user %s is saved to its TaskIn directory.\n', TaskName(1:end-4), Username );
                    PrintOut({MsgVerbose ; MsgQuiet}, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                catch
                    save( fullfile(obj.JobManagerParam.TempJMDir,TaskName), 'TaskParam' );
                    MsgVerbose = sprintf( 'Task file %s for user %s is saved to its TaskIn directory by OS.\n', TaskName(1:end-4), Username );
                    PrintOut({MsgVerbose ; MsgQuiet}, obj.JobManagerParam.vqFlag, obj.JobManagerParam.LogFileName);
                    OS_flag = 1;
                end
                
                if( rem(TaskCount,UserParam.TaskInFlushRate) == 0 )
                    PrintOut('\n', 0, obj.JobManagerParam.LogFileName);
                    if OS_flag ==1
                        % SuccessFlag = obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,'*.mat'), TaskInDir, SuccessMsg, ErrorMsg);
                        obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']), TaskInDir);
                        OS_flag = 0;
                    end
                end
                
                % Pause briefly for flow control.
                pause( UserParam.PauseTime );
            end
            
            PrintOut('\n', 0, obj.JobManagerParam.LogFileName);
            if OS_flag == 1
                % SuccessFlag = obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']), TaskInDir, SuccessMsg, ErrorMsg);
                obj.MoveFile(fullfile(obj.JobManagerParam.TempJMDir,[obj.JobManagerParam.ProjectName '_' JobName(1:end-4) '_Task_*.mat']), TaskInDir);
            end
            FinalTaskID = UserParam.TaskID;
        end
        
        
        function [FinalTaskID, JobState] = DivideJob2Tasks(obj, JobParam, JobState, UserParam, NumNewTasks, JobName, TaskMaxRunTime)
            % Divide the JOB into multiple TASKs.
            % Calling syntax: [FinalTaskID, JobState] = obj.DivideJob2Tasks(JobParam, JobState, UserParam, NumNewTasks, JobName [,TaskMaxRunTime])
            if( nargin<6 || isempty(TaskMaxRunTime) )
                if( isfield(JobParam, 'MaxRunTime') && (JobParam.MaxRunTime ~= -1) )
                    TaskMaxRunTime = JobParam.MaxRunTime;
                else
                    TaskMaxRunTime = UserParam.MaxRunTime;
                end
            end
            FinalTaskID = UserParam.TaskID;
            
            % [HomeRoot, Username, Extension, Version] = fileparts(UserParam.UserPath);
            % [Dummy, Username] = fileparts(UserParam.UserPath);
            Username = obj.FindUsername(UserParam.UserPath);
            
            if NumNewTasks > 0
                % Msg = sprintf( 'Generating %d NEW TASK files corresponding to JOB %s of user %s and saving them to its TaskIn directory at %s.\n\n',...
                %     NumNewTasks, JobName(1:end-4), Username, datestr(clock, 'dddd, dd-mmm-yyyy HH:MM:SS PM') );
                % PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
                
                % Calculate TaskInputParam vector for NumNewTasks new input tasks.
                TaskInputParam = obj.CalcTaskInputParam(JobParam, JobState, NumNewTasks);
                if( (length(TaskInputParam) == 1) && (NumNewTasks ~= 1) )
                    TaskInputParam = repmat(TaskInputParam, NumNewTasks, 1);
                end
                if ~isempty(TaskInputParam)
                    % Save new task files.
                    FinalTaskID = obj.SaveTaskInFiles(TaskInputParam, UserParam, JobName, TaskMaxRunTime);
                end
            else    % TaskInDir of the current user is full. No new tasks will be generated.
                Msg = sprintf('No new task is generated for user %s since its TaskIn directory is full.\n', Username);
                PrintOut(Msg, 0, obj.JobManagerParam.LogFileName);
            end
        end
        
        
        function TaskOutFileIndex = FindFinishedTask2Read(obj, NumTaskOut)
            % Pick a finished task file at random.
            TaskOutFileIndex = randi( [1 NumTaskOut], [1 1] );
        end
    end
end
