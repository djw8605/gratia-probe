#!/bin/bash
#
# pbs-lsfr_meter.cron.sh - Shell script used with cron to parse PBS and LSF
#   files for OSG accounting data collection.
#      By Chris Green <greenc@fnal.gov>  Began 5 Sept 2006
###################################################################
function check_if_running {
  # Need to be sure there is not one of these running already
  # This may not be the best way to test this for the long term ??? ###
  # If one is not running, then we need to remove a lock file that the
  # ./urCollector.pl and ./pbs-lsf_meter.pl processes check for.
  # Note: this lock file gets left behind when either of these processes
  #       ends prematurely like on a system shutdown.
    
  NCMeter=`ps -ef | egrep "\./urCollector.pl|\./pbs-lsf_meter.pl" | grep -v grep | wc -l`
  get_lockfile
  if [ -f $LOCKFILE ];then
    if [ ${NCMeter} -ne 0 ]; then
      return 1 
    else
      rm -f $LOCKFILE
    fi
  else
    mkdir -p `dirname "$LOCKFILE"`
  fi
  return 0
} # end of terminate_if_running
#------------------------
function get_lockfile {
  conf=$URCOLLECTOR_LOCATION/urCollector.conf
  if [ ! -f $conf ];then
    ${Logger} "ERROR: Unable to locate $conf"
    exit -1
  fi
  LOCKFILE=$(perl <<EOF
use urCollector::Configuration;
# Parse configuration file
&parseConf("$conf");
print "\$configValues{collectorLockFileName}";
exit(0);
EOF
)
} # end of get_lockfile
###################################################################
PGM=$(basename $0)
Logger="/usr/bin/logger -s -t $PGM"

Meter_BinDir=$(dirname $0)
if [ "x$1" != "x" ] ; then
   probeconfig_loc=$1
else
   probeconfig_loc=/etc/gratia/pbs-lsf/ProbeConfig
fi

# Set the working directory, where we expect to find the following
#    necessary files.
if [ -d ${Meter_BinDir} ]; then
  cd ${Meter_BinDir}
else
  ${Logger} "No such directory ${Meter_BinDir}"
  exit -1
fi

# We need to locate the probe script and it must be executable
if [ ! -x urCollector.pl ]; then
  ${Logger} "The urCollector.pl file is not in this directory: $(pwd)"
  exit -2
fi

# We need to locate these files and they must be readable
for Needed_File in ${probeconfig_loc}
do
  if [ ! -f ${Needed_File} ]; then
    ${Logger} \
     "The ${Needed_File} file is not in this directory: $(pwd)"
    exit -3
  fi
done

pp_dir=$(cd "$Meter_BinDir/../common"; pwd)

export URCOLLECTOR_LOCATION=`pwd`  

#--- check to see if processes still running --
check_if_running;rtn=$?
if [ $rtn -eq 1 ];then
   ${Logger} "urCollector.pl or pbs-lsf_meter.pl probes still running... exiting"
  exit 0
fi

enabled=`${pp_dir}/GetProbeConfigAttribute -c $probeconfig_loc EnableProbe`
(( status = $? ))
if (( $status != 0 )); then
  echo "ERROR checking probe configuration!" 1>&2
  exit $status
fi
if [[ -n "$enabled" ]] && [[ "$enabled" == "0" ]]; then
  ${pp_dir}/DebugPrint -c $probeconfig_loc -l -1 "Probe is not enabled: check probeconfig_loc."
  exit 1
fi

log_file="`date +'%Y-%m-%d'`.log"

#--- run the probes ----
./urCollector.pl --nodaemon 2>&1 | ${pp_dir}/DebugPrint -c $probeconfig_loc -l 1
# Now invoked by urCollector.pl
#./pbs-lsf_meter.pl 2>&1

ExitCode=$?

# If the probe ended in error, report this in Syslog and exit
if [ $ExitCode != 0 ]; then
  ${pp_dir}/DebugPrint -c $probeconfig_loc -l -1 "ALERT: $0 exited abnormally with [$ExitCode]"
  exit $ExitCode
fi
  
exit 0

