% staw.m
%
% Start a single worker.
%
% Version 2
% 12/26/2011
% Terry Ferrett

function staw(obj, wid)

% execute shell command to start worker - so -shell out
[stat pid] = so(obj, wid)

% store the pid in the worker object
obj.workers{wid}.pid = pid;

% start the worker by executing the command string
%[stat pid] = system(worker.stac);



% create the command string which stops the worker
%worker.stoc = ccs(obj, worker);

end





function [stat pid] = so(obj, wid)


  [bg iqr] = strtok(obj.gq.iq{1}, '/');
  [bg rqr] = strtok(obj.gq.rq{1}, '/');
  [bg oqr] = strtok(obj.gq.oq{1}, '/');
  [bg lp] = strtok(obj.lp{1}, '/');

iqr = ['/rhome' iqr]
rqr = ['/rhome' rqr]
oqr = ['/rhome' oqr]
  lp =  ['/rhome' lp '/' int2str(wid) '.log'];


cs = [obj.bs{1}  '/start_worker.sh'];
cs = [cs, ' ',...
	obj.workers{wid}.node, ' ',...
	obj.gwp{1}, ' ',...
	obj.gwn{1}, ' ',...
    int2str(wid), ' ', ...
	iqr, ' ',...
        rqr, ' ',...
        oqr,' '...
        lp]%

cs
  [stat pid] = system(cs);

end