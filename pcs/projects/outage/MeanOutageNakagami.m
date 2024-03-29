classdef MeanOutageNakagami< OutageNakagami
    
    % Computes outage probability averaged over a BPP given the size of the
    % annular network arena and the number of nodes placed there
    
    % by S. Talarico
    
    properties
        Beta              % SINR threshold
        Gamma             % Average signal-to-noise ratio(SNR) at unit distance (Vector)
        p                 % Probability of collisions
        integral          % Computation of the integral 
        integralFibp      % Computation of the integral for the adjacent channels
        alpha             % path loss exponent
        r_net             % outer radius of the anular area
        r_ex              % inner radius of the anular area
        TableDir          % link to indices and integral tables
        c_i               % takes into account DS spread-spectrum by c_i=(G/h)*(P_0/P_i), where:
        % - G: processing Gain;
        % - h: Chip factor.
        Fibp              % fractional in-band power       
%%%%%%%%% These properties are inherited from OutageNakagami %%%%%%%%%             
%       m                 % Nakagami shape factor for the source link
%       m_i               % Nakagami factor for the interfereres (length M vector)
%       M                 % Number of nodes
%       indices           % The set of indices summing to r
%       coefficients      % The multinomial coefficients used inside the outage probability's product
%%%%%%%%%    
    end
    
    properties (GetAccess='private' , SetAccess='private')
        % These are private so that they hopefully won't get stored when doing a save command
    end
    
    methods
        % constructor
        function obj = MeanOutageNakagami( r_net ,r_ex,alpha,m,m_i,M,PG, varargin )

            if nargin==7
                TableDir=[];
            else
                TableDir=varargin{1};
            end          
            
            % create indices and coefficients by inheriting from OutageNakagami
            obj@OutageNakagami(zeros(1,M),m,m_i,TableDir);
            
            obj.r_net = r_net;
            obj.r_ex  = r_ex;
            obj.alpha = alpha;
            obj.c_i=PG;
            
        end
                       
        function obj = ComputeIntegral( obj, Beta )
            % creates a structure with the value of the integrals
            elli=unique(obj.indices{1});
            integral_elli=obj.indices{1};
            
            for i=1:length(elli)
                integral_elli(find((integral_elli-elli(i))==0))=(obj.m_i^obj.m_i)/((Beta*obj.m)^(obj.m_i+elli(i)))*(obj.I_function(elli(i),Beta,obj.c_i*obj.r_net^obj.alpha)-obj.I_function(elli(i),Beta,obj.c_i*obj.r_ex^obj.alpha));
            end
            obj.integral{1} =integral_elli;
            
            for r=1:(obj.m-1)
                elli=unique(obj.indices{r+1});
                integral_elli=obj.indices{r+1};
                
                for i=1:length(elli)
                    integral_elli(find((integral_elli-elli(i))==0))=(obj.m_i^obj.m_i)/((Beta*obj.m)^(obj.m_i+elli(i)))*(obj.I_function(elli(i),Beta,obj.c_i*obj.r_net^obj.alpha)-obj.I_function(elli(i),Beta,obj.c_i*obj.r_ex^obj.alpha));
                end
                obj.integral{r+1}=integral_elli;
            end
        end
        
        function obj = ComputeIntegralFibp( obj, Beta, Fibp )
            % creates a structure with the value of the integrals
            elli=unique(obj.indices{1});
            integral_elli=obj.indices{1};
            integral_elli_Fibp=obj.indices{1};
            
            for i=1:length(elli)
                integral_elli(find((integral_elli-elli(i))==0))=Fibp^(elli(i))*(obj.m_i^obj.m_i)/((Beta*obj.m)^(obj.m_i+elli(i)))*(obj.I_function(elli(i),Beta,obj.c_i*obj.r_net^obj.alpha)-obj.I_function(elli(i),Beta,obj.c_i*obj.r_ex^obj.alpha));
                integral_elli_Fibp(find((integral_elli_Fibp-elli(i))==0))=(Fibp^(obj.m_i+elli(i))*obj.m_i^(obj.m_i)/((Beta*obj.m)^(obj.m_i+elli(i))*((1-Fibp)/2)^(obj.m_i)))*(obj.I_functionFibp(elli(i),Beta,Fibp,obj.c_i*obj.r_net^obj.alpha)-obj.I_functionFibp(elli(i),Beta,Fibp,obj.c_i*obj.r_ex^obj.alpha));
            end
            obj.integralFibp{1} =integral_elli_Fibp;
            obj.integral{1} =integral_elli;
            
            for r=1:(obj.m-1)
                elli=unique(obj.indices{r+1});
                integral_elli=obj.indices{r+1};
                integral_elli_Fibp=obj.indices{r+1};
                
                for i=1:length(elli)
                    integral_elli(find((integral_elli-elli(i))==0))=Fibp^(elli(i))*(obj.m_i^obj.m_i)/((Beta*obj.m)^(obj.m_i+elli(i)))*(obj.I_function(elli(i),Beta,obj.c_i*obj.r_net^obj.alpha)-obj.I_function(elli(i),Beta,obj.c_i*obj.r_ex^obj.alpha));
                    integral_elli_Fibp(find((integral_elli_Fibp-elli(i))==0))=(Fibp^(obj.m_i+elli(i))*obj.m_i^(obj.m_i)/((Beta*obj.m)^(obj.m_i+elli(i))*((1-Fibp)/2)^(obj.m_i)))*(obj.I_functionFibp(elli(i),Beta,Fibp,obj.c_i*obj.r_net^obj.alpha)-obj.I_functionFibp(elli(i),Beta,Fibp,obj.c_i*obj.r_ex^obj.alpha));
                end
                obj.integralFibp{r+1}=integral_elli_Fibp;
                obj.integral{r+1}=integral_elli;
            end
        end
        
        function I = I_function ( obj,l_i,Beta,y)
            % Compute the value of the I(y) function
            I =(obj.alpha*y^(2/obj.alpha+obj.m_i)*hypergeom([l_i+obj.m_i, obj.m_i+2/obj.alpha], obj.m_i+2/obj.alpha+1,-obj.m_i*y/(Beta*obj.m)))/(obj.alpha*obj.m_i+2);
        end
        
        function I = I_functionFibp ( obj, l_i, Beta, Fibp, y)
            % Compute the value of the I_1(y) function
            I =(obj.alpha*y^(2/obj.alpha+obj.m_i)*hypergeom([l_i+obj.m_i, obj.m_i+2/obj.alpha], obj.m_i+2/obj.alpha+1,-obj.m_i*y*Fibp/(Beta*obj.m*(1-Fibp)/2)))/(obj.alpha*obj.m_i+2);
        end
        
        
        function epsilon = ComputeSingleOutageSplatter( obj, Gamma, Beta, p, Fibp )
            % computes the outage for a single set of beta, gamma, and p
            
            %Compute the integrals for each set of indices for the
            %multiindex summation
            
            if isempty(obj.TableDir)
                
                % no directory specified, create the index tables
               
                if Fibp~=1
                    obj.ComputeIntegralFibp(Beta,Fibp);
                else
                   obj.ComputeIntegral(Beta ); 
                end
                
            else
                % build the name of the index table
                
                BetadB=10*log10(Beta);
                
                if Fibp~=1
                    IntegralTable = [obj.TableDir 'IntegralM' int2str( obj.M ) 'm' int2str(obj.m) 'mi' int2str(obj.m_i) 'Beta' num2str(round(BetadB*100)) ...
                        'r_net' int2str(obj.r_net*100) 'r_ex' num2str(round(obj.r_ex*100)) 'alpha' num2str(round(obj.alpha*100)) 'PG' num2str(round(obj.c_i*100)) 'Fibp' num2str(round( Fibp*1000)) '.mat'];
                else
                    IntegralTable = [obj.TableDir 'IntegralM' int2str( obj.M ) 'm' int2str(obj.m) 'mi' int2str(obj.m_i) 'Beta' num2str(round(BetadB*100)) ...
                        'r_net' int2str(obj.r_net*100) 'r_ex' num2str(round(obj.r_ex*100)) 'alpha' num2str(round(obj.alpha*100)) 'PG' num2str(round(obj.c_i*100)) '.mat'];
                end
                
                try
                    % try to load the file
                    if Fibp~=1
                        load( IntegralTable, 'integral','integralFibp' );
                        % it loaded, assign results to integral_elli
                        obj.integral = integral;
                        obj.integralFibp = integralFibp;
                        
                    else
                        load( IntegralTable, 'integral' );
                        % it loaded, assign results to integral_elli
                        obj.integral = integral;
                    end
                catch 
                    if Fibp~=1
                        obj.ComputeIntegralFibp(Beta,Fibp);
                        integralFibp = obj.integralFibp ;
                        integral = obj.integral;
                        
                        save( IntegralTable, 'integral','integralFibp' );
                    else
                        % it did not load, so create the integral tables
                        obj.ComputeIntegral(Beta );
                        % save it
                        integral = obj.integral;
                        save( IntegralTable, 'integral' );
                    end
                end
            end
            
            % evaluate the cdf at Gamma^-1
            z = 1./Gamma;
            % determine how many SNR points
            NumberSNR = length( Gamma );
            
            % initialize epsilon
            epsilon = zeros(1,NumberSNR);
            sum_s = zeros(1,NumberSNR);
            
            for s=0:obj.m-1
                sum_r = zeros(1,NumberSNR);
                for r=0:s
                    sum_ell = 0;
                    for ellset=1:size( obj.indices{r+1}, 1)
                        elli = obj.indices{r+1}(ellset,:); % the vector of indices
                        coef = obj.coefficients{r+1}(ellset,:); % the multinomial coefficients
                        coef_integral = obj.integral{r+1}(ellset,:);
                        factors = coef.*coef_integral;
                        if Fibp~=1
                            coef_integral1 = obj.integralFibp{r+1}(ellset,:);
                            factors1 = coef.*coef_integral1;
                            sum_ell = sum_ell + prod( ((repmat(p',1,obj.M).*repmat(factors,length(p),1)+ (repmat((2*p-2*p.^2)',1,obj.M).*repmat(factors1,length(p),1))).*(2/(obj.alpha*obj.c_i^(2/obj.alpha)*(obj.r_net^2-obj.r_ex^2))) + repmat((1-(3*p-2*p.^2))',1,obj.M).*repmat((elli==0),length(p),1))');
                        else
                            sum_ell = sum_ell + prod( (repmat(p',1,obj.M).*repmat(factors*(2/(obj.alpha*obj.c_i^(2/obj.alpha)*(obj.r_net^2-obj.r_ex^2))),length(p),1)+ repmat((1-p)',1,obj.M).*repmat((elli==0),length(p),1))') ;
                        end
                    end
                    sum_r = sum_r + z.^(-r)*sum_ell/factorial(s-r);
                end
                sum_s = sum_s + ((Beta/Fibp*obj.m*z).^s).*sum_r;
            end
            epsilon = 1 - sum_s.*exp(-Beta/Fibp*obj.m*z);
            
        end
        
        function epsilon = ComputeSingleOutage( obj, Gamma, Beta, p )
            % computes the outage for a single set of beta, gamma, and p
            
            %Compute the integrals for each set of indices for the
            %multiindex summation
                       
            if isempty(obj.TableDir)
                  
                % no directory specified, create the index tables
                obj.ComputeIntegral(Beta );
                                
            else               
                % build the name of the index table
                
                BetadB=10*log10(Beta);
                IntegralTable = [obj.TableDir 'IntegralM' int2str( obj.M ) 'm' int2str(obj.m) 'mi' int2str(obj.m_i) 'Beta' num2str(round(BetadB*100)) ...
                    'r_net' int2str(obj.r_net*100) 'r_ex' num2str(round(obj.r_ex*100)) 'alpha' num2str(round(obj.alpha*100)) 'PG' num2str(round(obj.c_i*100)) '.mat'];
                
                try
                    % try to load the file
                    load( IntegralTable, 'integral' );
                    % it loaded, assign results to integral_elli
                    obj.integral = integral;
                    
                catch
                    % it did not load, so create the integral tables
                    obj.ComputeIntegral(Beta );
                    % save it
                    integral = obj.integral;
                    save( IntegralTable, 'integral' );
                end
            end
            

            % evaluate the cdf at Gamma^-1
            z = 1./Gamma;
            % determine how many SNR points
            NumberSNR = length( Gamma );
            
            % initialize epsilon
            epsilon = zeros(1,NumberSNR); 
            sum_s = zeros(1,NumberSNR);
            
            for s=0:obj.m-1
                sum_r = zeros(1,NumberSNR);
                for r=0:s
                    sum_ell = 0;
                    for ellset=1:size( obj.indices{r+1}, 1)
                        elli = obj.indices{r+1}(ellset,:); % the vector of indices
                        coef = obj.coefficients{r+1}(ellset,:); % the multinomial coefficients
                        coef_integral = obj.integral{r+1}(ellset,:);  
                        factors = coef.*coef_integral;
                        sum_ell = sum_ell + prod( (repmat(p',1,obj.M).*repmat(factors*(2/(obj.alpha*obj.c_i^(2/obj.alpha)*(obj.r_net^2-obj.r_ex^2))),length(p),1)+ repmat((1-p)',1,obj.M).*repmat((elli==0),length(p),1))') ;
                    end
                    sum_r = sum_r + z.^(-r)*sum_ell/factorial(s-r);
                end
                sum_s = sum_s + ((Beta*obj.m*z).^s).*sum_r;
            end
            epsilon = 1 - sum_s.*exp(-Beta*obj.m*z);
            
        end
        
        function epsilon = ComputeOutage( obj, Gamma, Beta, p, varargin )
            % computes the outage for vector Beta, Gamma, and p
            

            % output will be a 3-D matrix
            %   dimension 1 is Gamma
            D1 = length( Gamma );
            %   dimension 2 is Beta
            D2 = length( Beta );
            %   dimension 3 is p
            D3 = length( p );
            
            % if defined, the fourth dimension is the fraction of inband power
            if (nargin==5)
                Fibp = varargin{1}; % fraction of inband power
                D4 = length( Fibp );
                epsilon = zeros( D3,D1, D2,  D4 ); % preallocate
            else
                epsilon = zeros(D3,D1,D2);  % preallocate
            end

            for j=1:D1
                for i=1:D2
                    if (nargin==5)
                        for q=1:D4
                            % p is given as a vector
                            epsilon(:,j,i,q) = obj.ComputeSingleOutageSplatter( Gamma(j), Beta(i), p, Fibp(q) ) ;
                        end
                    else
                            % p is given as a vector
                        epsilon(:,j,i) =  obj.ComputeSingleOutage( Gamma(j), Beta(i), p ) ;
                    end
                end
            end
        end
    end
    
end

