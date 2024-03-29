#!/bin/bash
# start_worker.sh
# Inputs
#  1. Worker path
#  2. hostname
#  3. Worker ID

# Input variables.
hostname=$1
worker_path=$2
worker_exe=$3
worker_id=$4
iq=$5
rq=$6
oq=$7
lf=$8
log_period=$9
num_logs=${10}
verbose_mode=${11}
wsp=${12}   # worker sweep period 10/2013


# Connect to the node and start the worker as a daemon.
ssh $hostname "export MATLABPATH=$worker_path; nohup matlab -r $worker_exe\($worker_id,\'$iq\',\'$rq\',\'$oq\',\'$lf\',\'$log_period\',\'$num_logs\',\'$verbose_mode\',\'$wsp\'\) >> $lf 2>&1 &"



# Get the process ID.
ssh $hostname "ps -ef" |grep -i "matlab -r $worker_exe($worker_id," | awk '{ print $2 }'
