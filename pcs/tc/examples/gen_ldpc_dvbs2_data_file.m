clear classes


example_root = pwd;  % example directory
cd ..; cd ..; cd ..; cd('projects'); cd('cml2'); 
CmlStartup;
cd('mat'); matroot = pwd; % mat directory
cd(example_root);




SNRdB = -5:0.5:5;

DVBS2Param = struct(...
    'EffectiveRate', 1/2,...
    'FrameSize', 64800,...
    'SNR', SNRdB,...             % Row vector of SNR points in dB.
    'MaxIteration', 30,...    % Maximum number of message passing decoding iterations for LDPC decoding (Default MaxIteration=30).
    'DecoderType', 0,...      % Message passing LDPC decoding algorithm: =0 (sum-product) (DEFAULT), =1 (min-sum), =2 (approximate min-sum).
    'ModulationObj', QPSK(),...
    'DemodType', 0,...        % Type of max_star algorithm that is used in demaping.
    'ZeroRandFlag', 0,...     % A binary flag which is used when input vector to the encoder DataBits is not given to Encode method of CodedModulation class.
    'OutputFileName', 'QPSK_DVBS2.mat');




TaskParam = struct(...
    'FunctionName', 'launch_ldpc',...
    'FunctionPath', '/rhome/tferrett/cml2/iscml/cml2/mat',...
    'InputParam', DVBS2Param,...
    'OutputFileName', 'QPSK_DVBS2.mat');


save('ldpc_dvbs2_task.mat','TaskParam');

