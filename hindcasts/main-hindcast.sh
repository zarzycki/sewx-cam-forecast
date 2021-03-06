#!/bin/bash

##=======================================================================
#PBS -N wx-driver
#PBS -A P54048000 
#PBS -l walltime=6:00:00
#PBS -q share
#PBS -k oe
#PBS -m a 
#PBS -M zarzycki@ucar.edu
#PBS -l select=1:ncpus=8
##=======================================================================

###################################################################################
# Colin Zarzycki (zarzycki@ucar.edu)
#
# Driver script for running CESM/CAM in "forecast" or "hindcast" mode.
# This code will either read UTC unix clock or read in a specified list of dates,
# download dataset, map to CAM grid, and run a forecast.
#
# Generally can be executed on login nodes or in the background, ex:
# $> nohup ./main-realtime.sh &
# but see above for example of PBS options to submit to batch nodes
#
# Details can be found in:
# C. M. Zarzycki and C. Jablonowski (2015), Experimental tropical cyclone forecasts 
# using a variable-resolution global model. Mon. Weat. Rev., 143(10), 4012–4037.
# doi:10.1175/MWR-D-15-0159.1.
###################################################################################

set -e
#set -v

#source /glade/apps/opt/lmod/lmod/init/bash
module load ncl

NAMELISTFILE=${1}
echo "Reading namelist ${NAMELISTFILE}..."
inputstream=`cat ${NAMELISTFILE}|grep -v "^#"`
set -- $inputstream
while [ $1 ]
 do
  echo "NAMELIST: setting ${1} to ${3}"
  eval $1=$3
  shift 3
 done

set -u  # turn on crashes for unbound variables in bash

###################################################################################
############### OPTIONS ############################################

# echo "debug set to $debug"
# echo "islive set to $islive" 
# echo "isliveresub set to $isliveresub"
# echo "machineid set to $machineid"
# echo "sendplots set to $sendplots" 
# echo "dotracking set to $dotracking"
# echo "runmodel set to $runmodel"
#               
# # Filter options (generally, only set doFilter unless you have a good reason to change defaults)
# echo "doFilter set to $doFilter" 
# echo "filterOnly set to $filterOnly" 
# 
# echo "casename is: ${casename}"
# echo "gfs2seWeights is: ${gfs2seWeights}"
# echo "nclPlotWeights is: ${nclPlotWeights}"
# echo "are we using CIME? ${usingCIME}"

###################################################################################
############### NEED TO BE SET BY USER ############################################

path_to_case=/glade/work/$LOGNAME/${casename}
pathToINICfiles=/glade/work/${LOGNAME}/sewx/INIC/
sePreFilterIC=${pathToINICfiles}/${casename}_INIC.nc
sePostFilterIC=${pathToINICfiles}/${casename}_INIC_filter.nc

pathToSSTfiles=/glade/work/${LOGNAME}/sewx/SST/
sstFileIC=${pathToSSTfiles}/sst_${casename}_1x1.nc

sewxscriptsdir=/glade/u/home/${LOGNAME}/sewx-cam-forecast/

gfs_files_path=/glade/work/$LOGNAME/sewx/GFS/          # Temp path for GFS/CFSR DL/proc
era_files_path=/glade/work/$LOGNAME/getECMWFdata/
sst_files_path=/glade/work/$LOGNAME/sewx/SST/          # Temp path for SST

path_to_rundir=/glade/scratch/$LOGNAME/${casename}/run/

upload_ncl_script=${sewxscriptsdir}/upload_ncl.sh

###################################################################################
############### OPTIONAL TO BE SET BY USER ########################################
path_to_nc_files=${path_to_rundir}              # Path where .nc files are
outputdir=${path_to_rundir}                     # Path where .nc files are being written
archivedir=${path_to_rundir}/proc/              # Path to temporarily stage final data
landdir=${path_to_rundir}/clmstart/             # Path to store CLM restart files
###################################################################################
### THESE COME WITH THE REPO, DO NOT CHANGE #######################################
gfs_to_cam_path=${sewxscriptsdir}/gfs_to_cam
era_to_cam_path=${sewxscriptsdir}/interim_to_cam
atm_to_cam_path=${sewxscriptsdir}/atm_to_cam
sst_to_cam_path=${sewxscriptsdir}/sst_to_cam
filter_path=${sewxscriptsdir}/filter
###################################################################################

## Create paths to generate initial files if they don't exist...
mkdir -p ${pathToINICfiles}
mkdir -p ${pathToSSTfiles}

# Set timestamp for backing up files, etc.
timestamp=`date +%Y%m%d.%H%M`
uniqtime=`date +"%s%N"`

echo "We are using ${casename} for the case"
echo "The formal SE run will start at +$numHoursSEStart hours from actual init time"

if [ $islive -ne 0 ]    # Find most recent GFS forecast
then
  ## Here we get two digit strings for UTC time for month, day, year
  ## We also get current time in hoursminutes (because the GFS output lags by 3.5 hours)
  monthstr=`date -u +%m`
  daystr=`date -u +%d`
  yearstr=`date -u +%Y`
  currtime=`date -u +%H%M`
  machzone=`date +%z`
  twodaysago=`date --date='2 days ago' -u +"%Y%m%d"`
  
  ## Use currtime to figure out what is the latest cycle we have access to
  if [ $currtime -lt 0328 ]
  then
    echo "18Z cycle"
    monthstr=`date --date="yesterday" -u +%m`
    daystr=`date --date="yesterday" -u +%d`
    yearstr=`date --date="yesterday" -u +%Y`
    twodaysago=`date --date='3 days ago' -u +"%Y%m%d"`
    cyclestr=18
  elif [ $currtime -lt 0928 ]
  then
    echo "00Z cycle"
    cyclestr=00
  elif [ $currtime -lt 1528 ]
  then
    echo "06Z cycle"
    cyclestr=06
  elif [ $currtime -lt 2128 ]
  then
    echo "12Z cycle"
    cyclestr=12
  elif [ $currtime -ge 2128 ]
  then
    echo "18Z cycle"
    cyclestr=18
  else
    echo "Can't figure out start time"
    exit 1
  fi
else     # if not live, draw from head of dates.txt file
  datesfile=dates.${casename}.txt
  longdate=$(head -n 1 ${datesfile})
  
  yearstr=${longdate:0:4}
  monthstr=${longdate:4:2}
  daystr=${longdate:6:2}
  cyclestr=${longdate:8:2}
  
  echo $yearstr
  echo $monthstr
  echo $daystr
  echo $cyclestr
  
  #Remove top line from dates file
  tail -n +2 ${datesfile} > ${datesfile}.2
  mv -v ${datesfile}.2 ${datesfile}
fi

## Figure out the seconds which correspond to the cycle and zero pad if neces
cyclestrsec=$(($cyclestr*3600))
echo $cyclestrsec
while [ ${#cyclestrsec} -lt 5 ];
do
  cyclestrsec="0"$cyclestrsec
done

## Figure out what the SE start time will be after filter
if [ $numHoursSEStart -lt 6 ]
then
  let se_cyclestr=$cyclestr+03
  while [ ${#se_cyclestr} -lt 2 ];
  do
    se_cyclestr="0"$se_cyclestr
  done
  echo $se_cyclestr

  se_monthstr=$monthstr
  se_daystr=$daystr
  se_yearstr=$yearstr
  let se_cyclestrsec=$((10#$se_cyclestr))*3600
  echo $se_cyclestrsec
  while [ ${#se_cyclestrsec} -lt 5 ];
  do
    se_cyclestrsec="0"$se_cyclestrsec
  done
else
  echo "SE forecast lead time too long, 18Z cycle causes trouble"
  echo "Not yet supported."
  exit 1
fi

if [ $islive -ne 0 ]
then
  ## Use currtime to figure out what SST we can download
  ## Current GDAS SST appears 555 after cycle time
  ## First guess is today's dates!
  sstmonthstr=$monthstr
  sstdaystr=$daystr
  sstyearstr=$yearstr
  if [ $currtime -lt 0555 ]
  then
    echo "SSTs are previous days 18Z"
    sstmonthstr=`date --date="yesterday" -u +%m`
    sstdaystr=`date --date="yesterday" -u +%d`
    sstyearstr=`date --date="yesterday" -u +%Y`
    sstcyclestr=18
  elif [ $currtime -lt 1155 ]
  then
    echo "SSTs are current days 00Z"
    sstcyclestr=00
  elif [ $currtime -lt 1755 ]
  then
    echo "SSTs are current days 06Z"
    sstcyclestr=06
  elif [ $currtime -lt 2355 ]
  then
    echo "SSTs are current days 12Z"
    sstcyclestr=12
  elif [ $currtime -ge 2355 ]
  then
    echo "SSTs are current days 18Z"
    sstcyclestr=18
  else
    echo "Can't figure out start time"
    exit 1
  fi
else
  sstmonthstr=$monthstr
  sstdaystr=$daystr
  sstyearstr=$yearstr
  sstcyclestr=$cyclestr
fi

yestmonthstr=`date --date="yesterday" -u +%m`
yestdaystr=`date --date="yesterday" -u +%d`
yestyearstr=`date --date="yesterday" -u +%Y`

echo "We are using $yearstr $monthstr $daystr $cyclestr Z ($cyclestrsec seconds) for GFS data"
echo "We are using $sstyearstr $sstmonthstr $sstdaystr $sstcyclestr Z for SST data"
echo "SE initialization will occur at $se_yearstr $se_monthstr $se_daystr $se_cyclestr Z ($se_cyclestrsec seconds)"

if $runmodel ; then

if [ $debug -ne 1 ]
then

############################### GET ATM DATA ############################### 

  if [ $atmDataType -eq 1 ] ; then
      echo "Using GFS forecast ICs"
      echo "Getting GFS conditions"
      mkdir -p $gfs_files_path
      cd $gfs_files_path
        ## Pull atmospheric conditions
        ## Need to write an if call depending on how far back the GFS files are located
        ## The NCEP server only holds them for a few days -- otherwise go to nomads at NCDC
        # gfsFtpPath=http://nomads.ncdc.noaa.gov/data/gfsanl/$yearstr$monstr/$yearstr$monstr$daystr/
        # gfs.t12z.pgrb2f00.grb2
        echo "Getting Atmo file"
        if [ $islive -ne 0 ]   # Pull data from GFS server
        then
          rm -f gfs.t*pgrb2f00*
          gfsFTPPath=ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/gfs/prod/gfs.$yearstr$monthstr$daystr$cyclestr/
          #gfsFTPFile='gfs.t'$cyclestr'z.pgrb2f00'
          gfsFTPFile='gfs.t'$cyclestr'z.pgrb2.0p25.anl'
          #gfsFTPFile='gfs.t'$cyclestr'z.pgrb2.0p50.anl'
          echo "Attempting to download ${gfsFTPPath}${gfsFTPFile}"
          ## Scrape for files
          error=1
          while [ $error != 0 ]
          do
            wget --quiet $gfsFTPPath$gfsFTPFile
            error=`echo $?`
            if [ $error -ne 0 ]
            then
              echo "Cannot get file, will wait 2 min and scrape again"
              sleep 120
            fi
          done
        else                  # Copy GFS data from RDA archive at NCAR
          rm -f gfs.t*pgrb2f00*
          gfsFTPPath=/glade2/collections/rda/data/ds084.1/${yearstr}/${yearstr}${monthstr}${daystr}/
          gfsFTPFile=gfs.0p25.${yearstr}${monthstr}${daystr}${cyclestr}.f000.grib2
          cp ${gfsFTPPath}/${gfsFTPFile} .
          echo "Attempting to copy ${gfsFTPPath}${gfsFTPFile}"
        fi
        mv $gfsFTPFile 'gfs_atm_'$yearstr$monthstr$daystr$cyclestr'.grib2'
  elif [ $atmDataType -eq 2 ] ; then  
      echo "Using ERA-Interim forecast ICs"
      echo "Cding to ERA-Interim interpolation directory"
      mkdir -p $era_files_path
      cd $era_files_path
      python getInterim.py ${yearstr}${monthstr}${daystr} ${cyclestr}
      ncks -A ERA-Int_ml_${yearstr}${monthstr}${daystr}${cyclestr}.nc ERA-Int_sfc_${yearstr}${monthstr}${daystr}${cyclestr}.nc
      mv -v ERA-Int_sfc_${yearstr}${monthstr}${daystr}${cyclestr}.nc ERA-Int_${yearstr}${monthstr}${daystr}${cyclestr}.nc
      rm -f ERA-Int_ml_${yearstr}${monthstr}${daystr}${cyclestr}.nc
  elif [ $atmDataType -eq 3 ] ; then  
      echo "Using CFSR ICs"
      echo "Cding to GFS interpolation directory since they are practically the same thing"
      mkdir -p $gfs_files_path
      cd $gfs_files_path
      STCUTARR=(26 21 16 11 06 01)
      ENCUTARR=(99 25 20 15 10 05)
      zero=0
      index=$zero
      for FILEDAY in "${STCUTARR[@]}"
      do
        if [ "$daystr" -ge "$FILEDAY" ]
        then
      #    echo $FILEDAY
          break
        fi
        index=$((index+1))
      done
      #echo $index
      if [[ "$index" -eq "$zero" ]]; then
        ENCUTARR[${zero}]=`date -d "$monthstr/1 + 1 month - 1 day" "+%d"`
        echo "Last day of month ($monthstr) is $ENCUTARR[${zero}]"
      fi
      ## NEED TO IMPLEMENT LEAP YEAR FIX
      CFSRFILENAME=pgbhnl.gdas.${yearstr}${monthstr}${FILEDAY}-${yearstr}${monthstr}${ENCUTARR[$index]}.tar
      echo "Getting file: ${CFSRFILENAME}"
      #Register with RDA, then do following command to get wget cookies
      #wget --save-cookies ~/.thecookies --post-data="email=your_email_address&passwd=your_password&action=login" https://rda.ucar.edu/cgi-bin/login
      wget --load-cookies ~/.thecookies http://rda.ucar.edu/data/ds093.0/${yearstr}/${CFSRFILENAME}
      
      tar -xvf $CFSRFILENAME
      mv pgbhnl.gdas.${yearstr}${monthstr}${daystr}${cyclestr}.grb2 'cfsr_atm_'$yearstr$monthstr$daystr$cyclestr'.grib2'
      rm pgbhnl.gdas.*
  else
      echo "Incorrect model IC entered"
      exit 1
  fi

############################### GET SST / NCL ############################### 

  if [ ${sstDataType} -eq 1 ] ; then
    SSTTYPE=GDAS
    ## Pull sea surface temps, need to rename and delete (if necess)
    #echo "Live GFS SST hasn't been updated in a while..." ; exit
    echo "Getting SST data"
    mkdir -p ${sst_files_path}
    cd ${sst_files_path}
    if [ $islive -ne 0 ] ; then
      # Here is where we get the "live" GDAS SST file
      rm -f gdas1*sstgrb*
      sstFTPPath=ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/gfs/prod/sst.${yestyearstr}${yestmonthstr}${yestdaystr}/
      sstFTPFile='rtgssthr_grb_0.5.grib2'
      echo "Attempting to download ${sstFTPPath}${sstFTPFile}"
    else
      echo "NCEP broke support for historical GDAS, use NOAAOI instead."
      exit
    fi
    ## Scrape for files
    error=1
    while [ $error != 0 ]
    do
      wget -nv $sstFTPPath$sstFTPFile
      error=`echo $?`
      if [ $error -ne 0 ]
      then
        echo "Cannot get file, will wait 2 min and scrape again"
        sleep 120
      fi
    done
    sstFile='gfs_sst_'$yearstr$monthstr$daystr$cyclestr'.grib2'
    mv ${sstFTPFile} ${sstFile}
    iceFile=''   # do not need icefile since ice stored on sstfile
  elif [ ${sstDataType} -eq 2 ] ; then  
    echo "ERA SST not quite supported yet..." ; exit 1
  elif [ ${sstDataType} -eq 3 ] ; then
    SSTTYPE=NOAAOI
    echo "Using NOAAOI SSTs"
    mkdir -p ${sst_files_path}
    cd ${sst_files_path}
    sstFile=sst.day.mean.${yearstr}.v2.nc
    if [ ! -f ${sst_files_path}/${sstFile} ] ; then
      echo "NOAAOI file doesn't exist, need to download"
      sstFTPPath=ftp://ftp.cdc.noaa.gov/Datasets/noaa.oisst.v2.highres/
      error=1
      while [ $error != 0 ]
      do
        wget -nv ${sstFTPPath}/${sstFile}
        error=`echo $?`
        if [ $error -ne 0 ]
        then
          echo "Cannot get file, will wait 2 min and scrape again"
          sleep 120
        fi
      done        
    fi
    iceFile=icec.day.mean.${yearstr}.v2.nc
    if [ ! -f ${sst_files_path}/${iceFile} ] ; then
      echo "NOAAOI file doesn't exist, need to download"
      sstFTPPath=ftp://ftp.cdc.noaa.gov/Datasets/noaa.oisst.v2.highres/
      error=1
      while [ $error != 0 ]
      do
        wget -nv ${sstFTPPath}/${iceFile}
        error=`echo $?`
        if [ $error -ne 0 ]
        then
          echo "Cannot get file, will wait 2 min and scrape again"
          sleep 120
        fi
      done        
    fi


  else
      echo "Incorrect SST data type entered" ; exit 1
  fi

  set +e
  cd ${sst_to_cam_path}
  (set -x; ncl sst_interp.ncl 'initdate="'${yearstr}${monthstr}${daystr}${cyclestr}'"' \
    'datasource="'${SSTTYPE}'"' \
    'sstDataFile = "'${sst_files_path}/${sstFile}'"' \
    'iceDataFile = "'${sst_files_path}/${iceFile}'"' \
    'SST_write_file = "'${sstFileIC}'"' )
  if [[ $? -ne 9 ]]
  then
    echo "NCL exited with non-9 error code"
    exit 240
  fi
  echo "SST NCL completed successfully"
  set -e # Turn error checking back on
  ncatted -O -a units,time,o,c,"days since 0001-01-01 00:00:00" ${sstFileIC} ${sstFileIC}

############################### ATM NCL ############################### 

  ## If we are not filtering, we need to make sure CAM writes INIC to correct file
  if [ "$doFilter" = false ] ; then
    sePreFilterIC=${sePostFilterIC}
  fi

  set +e #Need to turn off error checking b/c NCL returns 0 even if fatal
  ### We can probably clean this up by merging the above sed commands into command line arguments
  ### then put this if/else statement up inside the whole get data structure above
  if [ $atmDataType -eq 1 ] # GFS
  then
    echo "Cding to GFS interpolation directory"
    cd $atm_to_cam_path 
    echo "Doing NCL"

    (set -x; ncl -n atm_to_cam.ncl 'datasource="GFS"'     \
        numlevels=${numLevels} \
        YYYYMMDDHH=${yearstr}${monthstr}${daystr}${cyclestr} \
       'data_filename = "'$gfs_files_path'/gfs_atm_'$yearstr$monthstr$daystr$cyclestr'.grib2"'  \
       'wgt_filename="'${gfs2seWeights}'"' \
       'se_inic = "'${sePreFilterIC}'"' )
       
  elif [ $atmDataType -eq 2 ] # ERA
  then
    echo "CD ing to ERA-interim interpolation directory"
    cd $atm_to_cam_path

    (set -x; ncl -n atm_to_cam.ncl 'datasource="ERAI"'     \
        numlevels=${numLevels} \
        YYYYMMDDHH=${yearstr}${monthstr}${daystr}${cyclestr} \
       'data_filename = "/glade/p/work/zarzycki/getECMWFdata/ERA-Int_'$yearstr$monthstr$daystr$cyclestr'.nc"'  \
       'wgt_filename="/glade/p/work/zarzycki/getECMWFdata/ERA_to_uniform_60_patch.nc"' \
       'se_inic = "'${sePreFilterIC}'"' )

  elif [ $atmDataType -eq 3 ] # CFSR
  then
      echo "CD ing to interpolation directory"
      cd $atm_to_cam_path 
    
      (set -x; ncl -n atm_to_cam.ncl 'datasource="CFSR"'     \
        numlevels=${numLevels} \
        YYYYMMDDHH=${yearstr}${monthstr}${daystr}${cyclestr} \
       'data_filename = "'$gfs_files_path'/cfsr_atm_'$yearstr$monthstr$daystr$cyclestr'.grib2"'  \
       'wgt_filename="'${gfs2seWeights}'"' \
       'se_inic = "'${sePreFilterIC}'"' )
  else
      echo "Incorrect model IC entered"
      exit 1
  fi
  # Since NCL doesn't return non-zero codes, I have NCL returning a non-zero code
  # if successful! However, this means we have to check if code is successful with
  # something other than zero. Generally, if NCL fails expect a 0 return, but lets
  # be safe and call everything non-9.
  if [[ $? -ne 9 ]]
  then
    echo "NCL exited with non-9 error code"
    exit 240
  fi
  echo "ATM NCL completed successfully"
  set -e # Turn error checking back on
  
fi #End debug if statement

############################### #### ############################### 
##### ADD PERTURBATIONS

if [ "${add_perturbs}" = true ] ; then
  echo "Adding perturbations from Michael Wehner"

  cp /glade/scratch/zarzycki/apply-haiyan-perturb/sst_1x1_Nat-Hist-CMIP5-est1-v1-0.nc ${sstFileIC}

  cd $atm_to_cam_path

  sePreFilterIC_WPERT=${sePreFilterIC}_PERT.nc

  set +e
  ncl -n add_perturbations_to_cam.ncl 'BEFOREPERTFILE="'${sePreFilterIC}'"'  \
    'AFTERPERTFILE = "'${sePreFilterIC_WPERT}'"'
  if [[ $? -ne 9 ]]
  then
    echo "NCL exited with non-9 error code"
    exit 240
  fi
  echo "ATM NCL completed successfully"
  set -e # Turn error checking back on

  mv ${sePreFilterIC_WPERT} ${sePreFilterIC}

fi

############################### #### ############################### 
##### MODEL SETTINGS LOGIC

ATM_NCPL=`python -c "print int(86400/${DTIME})"`
STABILITY=`python -c "print 900*30/${FINE_NE}"`
SE_NSPLIT=`python -c "from math import ceil; print int(ceil(float(${DTIME})/float(${STABILITY})))"`
echo $STABILITY $ATM_NCPL $SE_NSPLIT
echo "${DTIME}s dt_phys means ${ATM_NCPL} coupling intervals/day"
echo "${DTIME}s dt_phys and fine res: ne${FINE_NE} = ${STABILITY}s CFL stability"
echo "${DTIME}s dt_phys and ${STABILITY}s dt_dyn --> se_nsplit: ${SE_NSPLIT}"

############################### #### ############################### 


cd $path_to_case
echo "Turning off archiving and restart file output in env_run.xml"
./xmlchange DOUT_S=FALSE,REST_OPTION=nyears,REST_N=9999
echo "Setting SST from default to our SST"
./xmlchange SSTICE_DATA_FILENAME="${sstFileIC}"
echo "Setting GLC coupling to handle forecasts across calendar years"
./xmlchange GLC_AVG_PERIOD="glc_coupling_period"
echo "Standardizing streams for SST"
./xmlchange SSTICE_YEAR_START=1,SSTICE_YEAR_END=1
####### 
if [ "$land_spinup" = true ] ; then
  ./xmlchange REST_OPTION=ndays,REST_N=1
fi
#######
echo "Update env_run.xml with runtime parameters"
./xmlchange RUN_STARTDATE=$yearstr-$monthstr-$daystr,START_TOD=$cyclestrsec,STOP_OPTION=ndays,STOP_N=$numdays

cp -v user_nl_cam_run user_nl_cam
sed -i 's?.*ncdata.*?ncdata='"'${sePreFilterIC}'"'?' user_nl_cam
./xmlchange ATM_NCPL=192

echo "Setting input land dataset"
# Clean up file to delete any special interp lines that may be needed later (but aren't needed for native init)
#sed -i '/finidat/d' user_nl_clm
sed -i '/init_interp_fill_missing_with_natveg/d' user_nl_clm
sed -i '/use_init_interp/d' user_nl_clm
#echo "finidat=''" >> user_nl_clm

# We want to check ${landdir} for clm restart files. If so, use those.
landrestartfile=${landdir}/${casename}.clm2.r.${yearstr}-${monthstr}-${daystr}-${cyclestrsec}.nc
echo $landrestartfile

# Check to see if file exists on native SE land grid
if [ -f ${landrestartfile} ]; then
   echo "File exists at exact time"
else
   echo "File does not exist at exact time"
   landrestartfile=${landdir}/${casename}.clm2.r.${yearstr}-${monthstr}-${daystr}-00000.nc
   if [ -f ${landrestartfile} ]; then
     echo "File exists at 00Z"
   else
     echo "No restart file exists, setting to empty string."
     landrestartfile=
   fi
fi
echo "landrestartfile: ${landrestartfile}"

## Now modify user_nl_clm
if [ ${landrestartfile} ] ; then
  sed -i 's?.*finidat.*?finidat='"'${landrestartfile}'"'?' user_nl_clm
else
  rawlandrestartfile=`ls ${landrawdir}/*.clm2.r.${yearstr}-${monthstr}-${daystr}-${cyclestrsec}.nc || true`   # check for file, suppress failed ls error if true
  echo "rawlandrestartfile: ${rawlandrestartfile}"
  if [ ! -z ${rawlandrestartfile} ]; then   # if rawlandrestartfile string is NOT empty, add it.
    sed -i 's?.*finidat.*?finidat='"'${rawlandrestartfile}'"'?' user_nl_clm
    echo "use_init_interp = .true." >> user_nl_clm
    echo "init_interp_fill_missing_with_natveg = .true." >> user_nl_clm
  else
    if ${preSavedCLMuserNL} ; then
      echo "Using pre-written user_nl_clm file"
      cp user_nl_clm_presave user_nl_clm
    else
      echo "ERROR: Land file DOES NOT EXIST, consider cold start"
      exit
      #sed -i 's?.*finidat.*?!finidat='"''"'?' user_nl_clm
    fi
  fi
fi

echo "Running again!" > ${path_to_rundir}/testrunning.gz

## Get number of log files archived
numlogfiles=`ls ${path_to_rundir}/*.gz | wc -l`

echo "numlogfiles: $numlogfiles"

if $doFilter ; then
  # If filtering, need to change these options
  cd $path_to_case
  ./xmlchange STOP_OPTION=nhours,STOP_N=${filterHourLength}
  cp -v user_nl_cam_filter user_nl_cam
  sed -i 's?.*ncdata.*?ncdata='"'${sePreFilterIC}'"'?' user_nl_cam
  ./xmlchange ATM_NCPL=192
  ./xmlchange JOB_WALLCLOCK_TIME=${FILTERWALLCLOCK}
  ./xmlchange JOB_QUEUE=${FILTERQUEUE}

  if [ $debug -ne 1 ] ; then
    echo "Begin call to filter-run"
    if [ $machineid -eq 1 ]
    then
      if $usingCIME ; then
        #./case.setup --reset
        #./case.build
        ./case.submit
      else
        bsub < ${casename}.run
      fi
    else
      echo "Unsupported machine" ; exit 1
    fi
    ## Hold script while log files from filter run haven't been archived yet

    while [ `ls ${path_to_rundir}/*.gz | wc -l` == $numlogfiles ]
    do
      sleep 20 ; echo "Sleeping... $(date '+%Y%m%d %H:%M:%S')"
    done
    echo "Run over done sleeping ($(date '+%Y%m%d %H:%M:%S')) will hold for 30 more sec to make sure files moved" ; sleep 40

    ## Run NCL filter
    cd $filter_path
    echo "Running filter"
    cp ${sePreFilterIC} ${sePostFilterIC}
    filtfile_name=${casename}.cam.h0.$yearstr-$monthstr-$daystr-$cyclestrsec.nc
    ncl lowmemfilter.ncl \
     endhour=${filterHourLength} tcut=${filtTcut} \
    'filtfile_name = "'${path_to_rundir}'/'${filtfile_name}'"' \
    'writefile_name = "'${sePostFilterIC}'"'
  fi  # debug

  echo "done with filter, removing filter files"
  mkdir -p $path_to_nc_files/filtered
  mv -v $path_to_nc_files/*.nc $path_to_nc_files/filtered
  ## Delete filter files that aren't h0 since those are the only ones we care about.
  find $path_to_nc_files/filtered/ -type f -not -name '*.cam.h0.*.nc' | xargs rm

  ## For now, I'm going to go back and delete all the h0 files in filtered
  rm -v $path_to_nc_files/filtered/*.cam.h0.*.nc

  ### Output filter files only, can be used for ensemble or other initialization after the fact
  if ${filterOnly} ; then
    FILTONLYDIR=${path_to_nc_files}/FILT_INIC/${se_yearstr}-${se_monthstr}-${se_daystr}-${se_cyclestrsec}
    mkdir -p ${FILTONLYDIR}
    cp ${sePostFilterIC} ${FILTONLYDIR}/${casename}_FILTERED_${se_yearstr}-${se_monthstr}-${se_daystr}-${se_cyclestrsec}.nc
    cp ${sstFileIC} ${FILTONLYDIR}/${casename}_SST_1x1_${se_yearstr}-${se_monthstr}-${se_daystr}-${se_cyclestrsec}.nc
    mkdir ${FILTONLYDIR}/config_files
    mv ${path_to_nc_files}/*.gz ${FILTONLYDIR}/config_files
    mv ${path_to_nc_files}/*.nml ${FILTONLYDIR}/config_files
    mv ${path_to_nc_files}/*_in ${FILTONLYDIR}/config_files
    exit
  fi

  echo "Make changes in CESM-SE namelist"
  cd $path_to_case
  ./xmlchange RUN_STARTDATE=$se_yearstr-$se_monthstr-$se_daystr,START_TOD=$se_cyclestrsec,STOP_OPTION=ndays,STOP_N=$numdays
  cp -v user_nl_cam_run user_nl_cam
  sed -i 's?.*ncdata.*?ncdata='"'${sePostFilterIC}'"'?' user_nl_cam
  ./xmlchange ATM_NCPL=${ATM_NCPL}
  ./xmlchange JOB_WALLCLOCK_TIME=${RUNWALLCLOCK}
  ./xmlchange JOB_QUEUE=${RUNQUEUE}

fi

if [ $debug -ne 1 ]
then
  echo "Begin call to forecast run"
  if [ $machineid -eq 1 ]
  then
    echo "Using Yellowstone"
    if $usingCIME ; then
      #bsub < case.run
      #./case.setup --reset
      #./case.build
      ./case.submit
    else
      bsub < ${casename}.run
    fi
  else
    echo "Unsupported machine" ; exit 1
  fi
  
  cd $outputdir
  
  echo "Running again!" > ${path_to_rundir}/testrunning.gz

  ## Get number of log files archived
  numlogfiles=`ls ${path_to_rundir}/*.gz | wc -l`

  echo "numlogfiles: $numlogfiles"

  ## Hold script while log files from filter run haven't been archived yet
  while [ `ls ${path_to_rundir}/*.gz | wc -l` == $numlogfiles ]
  do
    sleep 20 ; echo "Sleeping... $(date '+%Y%m%d %H:%M:%S')"
  done
  echo "Run over done sleeping ($(date '+%Y%m%d %H:%M:%S')) will hold for 30 more sec to make sure files moved"
  sleep 30
fi

fi # end run model

mkdir -p $archivedir
mkdir -p $archivedir/images
mkdir -p $archivedir/text
mkdir -p $archivedir/nl_files
mkdir -p $archivedir/logs
cd $outputdir

set +e

## Move other cam files to dir
mv *.cam.h*.nc $archivedir
cp *_in seq_maps.rc *_modelio.nml docn.streams.txt.prescribed $archivedir/nl_files
mv *.txt $archivedir/text
mv *.log.* $archivedir/logs
mv timing/ $archivedir/

## Move land files to new restart location
cd $path_to_nc_files
mkdir $landdir
echo "Removing 06Z and 18Z land restart files"
rm -v *.clm2.r.*32400.nc
rm -v *.clm2.r.*75600.nc
echo "Moving land restart files"
mv -v *.clm2.r.*nc $landdir
rm -v *.clm2.r.*.nc

echo "Deleting boring restart files"
# Delete boring restart files
cd $path_to_nc_files
rm -v *.clm2.rh0.*.nc
rm -v *.docn.rs1.*.bin
rm -v *.cam.r.*.nc
rm -v *.cam.rs.*.nc
rm -v *.cpl.r.*.nc
rm -v *.clm2.rh0.*.nc
rm -v *.cam.rh3.*.nc
rm -v *.cice.r.*.nc
rm -v rpointer.*

mv -v $archivedir ${outputdir}/${yearstr}${monthstr}${daystr}${cyclestr}

if $dotracking ; then
  cd /glade/u/home/zarzycki/tempest-scripts/forecast/
  rm -v tcvitals ATCF
  wget ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/gfs/prod/gfs.$yearstr$monthstr$daystr$cyclestr/gfs.t${cyclestr}z.syndata.tcvitals.tm00
  mv -v gfs.t${cyclestr}z.syndata.tcvitals.tm00 tcvitals
  if [ -f tcvitals ]; then
    /bin/bash ./drive-tracking.sh ${yearstr}${monthstr}${daystr}${cyclestr}
    cp -v ATCF fin-atcf/atcf.tempest.$yearstr$monthstr$daystr$cyclestr
    cp -v tcvitals fin-tcvitals/tcvitals.$yearstr$monthstr$daystr$cyclestr
  fi
  cd $path_to_nc_files
fi

if $sendplots ; then
  ### Begin output calls
  echo "Sending plots!"
  cp ${upload_ncl_script} ${upload_ncl_script}.${uniqtime}.ncl
  sed -i 's?.*yearstr=.*?yearstr='${yearstr}'?' ${upload_ncl_script}.${uniqtime}.ncl
  sed -i 's?.*monthstr=.*?monthstr='${monthstr}'?' ${upload_ncl_script}.${uniqtime}.ncl
  sed -i 's?.*daystr=.*?daystr='${daystr}'?' ${upload_ncl_script}.${uniqtime}.ncl
  sed -i 's?.*cyclestrsec=.*?cyclestrsec='${cyclestrsec}'?' ${upload_ncl_script}.${uniqtime}.ncl
  sed -i 's?.*cyclestr=.*?cyclestr='${cyclestr}'?' ${upload_ncl_script}.${uniqtime}.ncl
  /bin/bash ${upload_ncl_script}.${uniqtime}.ncl ${nclPlotWeights} ${outputdir}/${yearstr}${monthstr}${daystr}${cyclestr}
  # Cleanup
  rm ${upload_ncl_script}.${uniqtime}.ncl
fi

cd $sewxscriptsdir/hindcasts/

if [ $isliveresub -ne 0 ] ; then
  sleep 60
  nohup ./main-hindcast.sh ${NAMELISTFILE} &
fi

exit 0
