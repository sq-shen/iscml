% wc.m
%
% Abstract base class implementing the worker controller
% interface.
%
% Version 1
% 2/27/2011
% Terry Ferrett

classdef wc < handle
    
    properties (Abstract)
        workers % Array of worker objects
        maxWorkers % Maximum workers per node
        workerPath % Path to worker script.
    end
        
    methods (Abstract)
        wSta(obj)  % Start worker
        wSto(obj)  % Stop worker
        status(obj) % Return worker status
    end
    
end