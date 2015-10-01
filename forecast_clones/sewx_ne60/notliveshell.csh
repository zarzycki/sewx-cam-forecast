#!/bin/bash

# Name of the job - You'll probably want to customize this.
#SBATCH -J sewx_driver

# Standard out and Standard Error output files with the job number in the name.
#SBATCH -o CAM-%j.output
#SBATCH -e CAM-%j.error

# Specify the partition.
#SBATCH --partition=hi # other options are low, med, bigmem, serial.

#SBATCH -n 1
#SBATCH --exclude=c9-35,c8-35,c8-30,c8-31

################################################################

## 1 = Yellowstone, 2 = Flux, 3 = Agri

debug=0

# Set whether we are running forecast in realtime
# 0 no, we are using historical data
# 1 yes, we are running live
islive=0

# Set whether we want to send plots to external server
# 0 no
# 1 yes
sendplots=1

machineid=3

gridname=uniform_60
numHoursSEStart=3

# Set input data type
# 1 = GFS forecast ICs
# 2 = ERA-interim reanalysis
inputdatatype=1

date

if [ $islive -ne 0 ]
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
  #  exit
  fi
else
  longdate=$(head -n 1 dates.txt)
  
  yearstr=${longdate:0:4}
  monthstr=${longdate:4:2}
  daystr=${longdate:6:2}
  cyclestr=${longdate:8:2}
  
  echo $yearstr
  echo $monthstr
  echo $daystr
  echo $cyclestr
  
  #Remove top line from dates file
  tail -n +2 dates.txt > dates2.txt
  mv dates2.txt dates.txt
fi

## Figure out the seconds which correspond to the cycle and zero pad if neces
let cyclestrsec=$cyclestr*3600
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
  let se_cyclestrsec=$se_cyclestr*3600
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

echo "The current time is $currtime"
echo "We are using $yearstr $monthstr $daystr $cyclestr Z ($cyclestrsec seconds) for GFS data"
echo "We are using $sstyearstr $sstmonthstr $sstdaystr $sstcyclestr Z for SST data"
echo "SE initialization will occur at $se_yearstr $se_monthstr $se_daystr $se_cyclestr Z ($se_cyclestrsec seconds)"

if [ $machineid -eq 1 ]
then
  echo "Using Yellowstone"
  sewxscriptsdir=/glade/u/home/$LOGNAME/sewx/
  backupdir=/glade/u/home/$LOGNAME/scriptbackups
  gfs_files_path=/glade/u/home/$LOGNAME/sewx/GFS
  era_files_path=/glade/u/home/$LOGNAME/sewx/ERA
  gfs_to_cam_path=/glade/u/home/$LOGNAME/sewx/gfs_to_cam
  era_to_cam_path=/glade/home/zarzycki/obs_data_init/reanal_to_cam
  filter_path=/glade/u/home/$LOGNAME/sewx/filter
  path_to_se_build=/glade/u/home/$LOGNAME
  path_to_gz_touch=/glade/scratch/$LOGNAME/archive/$gridname/atm/logs
  path_to_nc_files=/glade/scratch/$LOGNAME/archive/$gridname/atm/hist
  outputdir=/glade/scratch/$LOGNAME/${gridname}/run
elif [ $machineid -eq 2 ]
then
  echo "Using UMich Flux"
  exit 1
elif [ $machineid -eq 3 ]
then
  echo "Using UCDavis Agri"
  sewxscriptsdir=/home/$LOGNAME/sewx/sewx_ne60/
  backupdir=/home/$LOGNAME/scriptbackups
  gfs_files_path=/home/$LOGNAME/sewx/GFS
  era_files_path=/home/$LOGNAME/getECMWFdata
  gfs_to_cam_path=/home/$LOGNAME/sewx/gfs_to_cam
  era_to_cam_path=/home/$LOGNAME/sewx/interim_to_cam
  filter_path=/home/$LOGNAME/sewx/filter
  path_to_se_build=/home/$LOGNAME
  path_to_gz_touch=$path_to_se_build/$gridname/run
  path_to_nc_files=$path_to_se_build/$gridname/run
  outputdir=/home/$LOGNAME/${gridname}/run
else
  echo "Machine"
fi

# 30 -> CAM5 physics
# 26 -> CAM4 physics
numlevels=30

##set string=$month$day
##echo $string

# Set timestamp for backing up files, etc.
timestamp=`date +%Y%m%d.%H%M`
mkdir -p $backupdir

if [ $debug -ne 1 ]
then
  if [ $inputdatatype -eq 1 ]
  then
      echo "Using GFS forecast ICs"
      echo "Getting GFS conditions"
      cd $gfs_files_path
      echo "Cding to GFS interpolation directory"
      cd $gfs_to_cam_path 
  elif [ $inputdatatype -eq 2 ]
  then  
      echo "Using ERA-Interim forecast ICs"
      echo "Cding to ERA-Interim interpolation directory"
      cd $era_files_path
      python getInterim.py ${yearstr}${monthstr}${daystr} ${cyclestr}
      echo "CD ing to ERA-interim interpolation directory"
      cd $era_to_cam_path 
  else
      echo "Incorrect model IC entered"
      exit 1
  fi

  # Right now we only need to sed for GFS, it would be nice if we could
  # merge the se_interp files for both GFS/ECMWF and make flexible
  # so we can add other data products (ex: CFSR, etc.)
  if [ $inputdatatype -eq 1 ] # GFS
  then  
    echo "Sedding commands in NCL interpolation scripts"
    cp se_interp.ncl $backupdir/se_interp.BAK.$timestamp
    sed 's?^numlevels.*?numlevels='$numlevels'?' se_interp.ncl > test.ncl
    mv test.ncl se_interp.ncl
    sed 's?^monthstr.*?monthstr="'$monthstr'"?' se_interp.ncl > test.ncl
    mv test.ncl se_interp.ncl
    sed 's?^yearstr.*?yearstr="'$yearstr'"?' se_interp.ncl > test.ncl
    mv test.ncl se_interp.ncl
    sed 's?^daystr.*?daystr="'$daystr'"?' se_interp.ncl > test.ncl
    mv test.ncl se_interp.ncl
    sed 's?^cyclestr.*?cyclestr="'$cyclestr'"?' se_interp.ncl > test.ncl
    mv test.ncl se_interp.ncl
  fi

### We can probably clean this up by merging the above sed commands into command line arguments
### then put this if/else statement up inside the whole get data structure above
  if [ $inputdatatype -eq 1 ] # GFS
  then
    ncl se_interp.ncl machineid=$machineid 'gridname = "'$gridname'"' 'gfs_filename = "'$gfs_files_path'/gfs_atm_'$yearstr$monthstr$daystr$cyclestr'.grib2"'
    ncl sst_interp.ncl initdate=${yearstr}${monthstr}${daystr}${cyclestr} 'sst_file_full = "'$gfs_files_path'/gfs_sst_'$yearstr$monthstr$daystr$cyclestr'.grib2"'
  elif [ $inputdatatype -eq 2 ] # ERA
  then
    #ncl se_interp.ncl machineid=$machineid 'gridname = "'$gridname'"' 'ERA_dir="'${era_files_path}'"'
    
    ncl -n se_interp.ncl machineid=$machineid \
      numlevels=$numlevels \
      YYYYMMDDHH=${yearstr}${monthstr}${daystr}${cyclestr} \
      'gridname = "'$gridname'"' \
      'ERA_dir="'${era_files_path}'"'

    ncl sst_interp.ncl 'YYYYMMDDHH="'${yearstr}${monthstr}${daystr}${cyclestr}'"' \
      'dataSource="ERAI"' \
      'sstDataFile = "'${era_files_path}'/ERA-Int_sfc_'$yearstr$monthstr$daystr$cyclestr'.nc"' \
      'iceDataFile = "'${era_files_path}'/ERA-Int_sfc_'$yearstr$monthstr$daystr$cyclestr'.nc"'  
  else
      echo "Incorrect model IC entered"
      exit 1
  fi
  
fi #End debug if statement

cd $path_to_se_build/$gridname

echo "Change date in FV namelist"
./xmlchange -file env_run.xml -id RUN_STARTDATE -val $yearstr-$monthstr-$daystr
./xmlchange -file env_run.xml -id START_TOD -val $cyclestrsec
./xmlchange -file env_run.xml -id STOP_OPTION -val nhours
./xmlchange -file env_run.xml -id STOP_N -val 6
cp user_nl_cam_filter user_nl_cam

echo "Setting input land dataset"
# Copy dummy lnd namelist over with commented "!finidat" line
# If input land DOES exist, we'll sed in the file and remove ! comment
# If it does not exist, we'll do nothing and let CESM use arbitrary ICs
cp user_nl_clm_dummy user_nl_clm
if [ -f /home/zarzycki/tcforecast_60_x4/run/clmstart/tcforecast_60_x4.clm2.r.${se_yearstr}-${se_monthstr}-${se_daystr}-${se_cyclestrsec}.nc ]
then
    echo "Land file exists, sedding that into CLM namelist"
    sed -i 's?!finidat.*?finidat='"'"/home/zarzycki/tcforecast_60_x4/run/clmstart/tcforecast_60_x4.clm2.r."${se_yearstr}"-"${se_monthstr}"-"${se_daystr}"-"${se_cyclestrsec}".nc"'"'?' user_nl_clm
else
    echo "Land file DOES NOT EXIST, will use arbitrary CESM spinup"
    echo "OK, Colin is cheating and using a different land file"
    echo "He really should specify 3-4 files by month as dummies instead of CESM cold starts"
    sed -i 's?!finidat.*?finidat='"'"/home/zarzycki/tcforecast_60_x4/run/clmstart/tcforecast_60_x4.clm2.r.2012-08-24-10800.nc"'"'?' user_nl_clm
fi

echo "Running again!" > $path_to_gz_touch/testrunning.gz

## Get number of log files archived
numlogfiles=`ls $path_to_gz_touch/*.gz | wc -l`

echo $numlogfiles

if [ $debug -ne 1 ]
then

  echo "Begin call to filter-run"
  if [ $machineid -eq 1 ]
  then
    bsub < $gridname.run
  elif [ $machineid -eq 2 ]
  then
    echo "Using UMich Flux"
    exit 1
  elif [ $machineid -eq 3 ]
  then
    sbatch $gridname.run
    echo "Skip me"
  else
    echo "Unsupported start time"
  fi

  ## Hold script while log files from filter run haven't been archived yet
  while [ `ls $path_to_gz_touch/*.gz | wc -l` == $numlogfiles ]
  do
    sleep 20
    echo "Sleeping"
  done
  echo "Run over done sleeping will hold for 60 more sec to make sure files moved"
  
  sleep 40

  ## Run NCL filter
  cd $filter_path
  echo "Running filter"
  filtfile_name=$gridname.cam.h0.$yearstr-$monthstr-$daystr-$cyclestrsec.nc
  ncl digifilter.ncl machineid=$machineid 'filtfile_name = "'$filtfile_name'"' 'gridname = "'$gridname'"'

fi

echo "done with filter, removing filter files"
mkdir -p $path_to_nc_files/filtered
mv $path_to_nc_files/*.nc $path_to_nc_files/filtered
## Delete filter files that aren't h0 since those are the only ones we care about.
find $path_to_nc_files/filtered/ -type f -not -name '*.cam.h0.*.nc' | xargs rm
## For now, I'm going to go back and delete all the h0 files in filtered
rm $path_to_nc_files/filtered/*.cam.h0.*.nc

echo "Make changes in CESM-SE namelist"
cd $path_to_se_build/$gridname
./xmlchange -file env_run.xml -id RUN_STARTDATE -val $se_yearstr-$se_monthstr-$se_daystr
./xmlchange -file env_run.xml -id START_TOD -val $se_cyclestrsec
./xmlchange -file env_run.xml -id STOP_OPTION -val ndays
./xmlchange -file env_run.xml -id STOP_N -val 10
cp user_nl_cam_run user_nl_cam

if [ $debug -ne 1 ]
then

  echo "Begin call to forecast run"
  if [ $machineid -eq 1 ]
  then
    bsub < $gridname.run
  elif [ $machineid -eq 2 ]
  then
    echo "Using UMich Flux"
    exit 1
  elif [ $machineid -eq 3 ]
  then
    sbatch $gridname.run
  else
    echo "Unsupported start time"
  fi
  
  echo "Entering a sleep for 10 min before NCL scrape"
  sleep 600
  echo "Done sleeping, time to start scraping for files to plot"
  
  #### Now scrape for NCL files      
  ## rm -rf `ls -tr | head -n 1`
  #ssh balloflight@s483.sureserver.com 'rm /home/balloflight/www/weather/current/*.png ; rm /home/balloflight/www/weather/current/*.txt'
  
  if [ $sendplots -ne 0 ]
  then
    echo "SSHings..."
    ssh balloflight@s483.sureserver.com "mkdir -p /home/balloflight/www/weather/current/${yearstr}${monthstr}${daystr}${cyclestr} ; \ 
         rm -rf /home/balloflight/www/weather/current/${twodaysago}${cyclestr} ; \
         cd /home/balloflight/www/weather/current/ ; \
         cp *cfg *html ${yearstr}${monthstr}${daystr}${cyclestr} ; \
         rm ${yearstr}${monthstr}${daystr}${cyclestr}/index.html "
  fi
  
  COUNTER=0
  MAXCOUNTER=3600
  DTIME=180
  procdir=$outputdir/proc
  
  mkdir -p $procdir
  mkdir -p $procdir/images
  mkdir -p $procdir/text
  mkdir -p $procdir/nl_files
  mkdir -p $procdir/logs
  cd $outputdir
  
  ## UPDATE html page
  if [ ! -f index.html ]; then
    cp index.HOLD index.html
    sed '/<!--FORECASTHEAD-->/ r htmltemplate.html' index.html > _index1.html
    sed -e "/$twodaysago${cyclestr}/d" _index1.html > _index2.html
    sed -e "s/YYYYMMDDHH/${yearstr}${monthstr}${daystr}${cyclestr}/" _index2.html > _index3.html
    mv _index3.html index.html
    rm _index*.html
    if [ $sendplots -ne 0 ]
    then
      scp index.html balloflight@s483.sureserver.com:/home/balloflight/www/weather/current
    fi
  fi
  
  while [  $COUNTER -lt 900 ]; do
    echo The starting counter is $COUNTER
    filenames=`ls ${gridname}*h1*.nc`
    numfiles=`ls ${gridname}*h1*.nc | wc -l`
    echo $numfiles
    if [ $numfiles -eq 0 ]
    then
      echo "Nothing found"
      let COUNTER=COUNTER+DTIME
    else
      sleep 8
      echo "Found at least one file"
      rename 's/^/_/' ${gridname}*h1*.nc
      newfiles=`ls _${gridname}*h1*.nc`
      for f in $newfiles
      do
        echo "Processing"
        ncl /home/zarzycki/ncl/sewx/weatherplot.ncl inisec=$cyclestrsec iniday=$daystr inimon=$monthstr iniyear=$yearstr 'filename="'$f'"' > ncl.output 2>&1
        if [ grep FileReadVar ncl.output ]; then
          sleep 8
          echo "Found an error"
          ncl /home/zarzycki/ncl/sewx/weatherplot.ncl inisec=$cyclestrsec iniday=$daystr inimon=$monthstr iniyear=$yearstr 'filename="'$f'"'
        fi
        rm ncl.output
      done
      
      ## Trim whitespace around pngs
      genpngs=`ls *png`
      for g in $genpngs
      do
        convert -trim +repage $g $g
      done
      
      ## Get file list in txt file for FLANIS viewer
      basins=(natl epac)
      outflds=(wind tmq flut prect 500vort shear850250)
  
      # Loop over items in outflds
      for basin in ${basins[*]}
      do
        for item in ${outflds[*]}
        do
            #printf "   %s\n" $item
            
            if [ ! -f ${item}_${basin}_files.txt ]; then
              echo "File not found!"
              ls -1 ${item}*${basin}*png > ${item}_${basin}_files_nopath.txt
            else
              mv ${item}_${basin}_files_nopath.txt orig_${item}_${basin}_files.txt
              ls -1 ${item}*${basin}*png > tocat_${item}_${basin}_files.txt
              cat orig_${item}_${basin}_files.txt tocat_${item}_${basin}_files.txt > ${item}_${basin}_files_nopath.txt
              rm tocat_${item}_${basin}_files.txt orig_${item}_${basin}_files.txt
            fi
            
            cp ${item}_${basin}_files_nopath.txt ${item}_${basin}_files.txt
            #sed -i.bak 's/^/##/' ${item}files.txt        
          
        done
      done
      
      ## Move files to server
      ## Google create remote directory if not existant
      ## use rysnc?
      if [ $sendplots -ne 0 ]
      then
        echo "Moving files to remote server"
        scp *.png *.txt balloflight@s483.sureserver.com:/home/balloflight/www/weather/current/${yearstr}${monthstr}${daystr}${cyclestr}
      fi
      
      mv *.png $procdir/images
  
      mv $newfiles $procdir
  
      let COUNTER=0
    fi
    echo Now sleeping $DTIME seconds
    sleep $DTIME
  done

fi

### Finish uploading index.html
printtime=`date -u`
sed -e 's/\"red/\"green/' index.html > _index4.html
sed -e "s/CURRENTLY UPDATING/COMPLETED AT $printtime/" _index4.html > _index5.html
mv _index5.html index.html
rm _index*html
if [ $sendplots -ne 0 ]
then
  scp index.html balloflight@s483.sureserver.com:/home/balloflight/www/weather/current
fi
mv index.html index.HOLD

## Move other cam files to dir
mv *.cam.h*.nc $procdir
cp *_in seq_maps.rc *_modelio.nml docn.streams.txt.prescribed $procdir/nl_files
mv *.txt $procdir/text
mv *.log.* $procdir/logs
mv timing/ $procdir/

## Move land files to new restart location
cd $path_to_nc_files
landdir=$path_to_nc_files/clmstart
mkdir $landdir
echo "Removing 06Z and 18Z land restart files"
rm *.clm2.r.*32400.nc
rm *.clm2.r.*75600.nc
echo "Moving land restart files"
##mv *.clm2.r.*nc $landdir
rm *.clm2.r.*.nc

echo "Deleting boring restart files"
# Delete boring restart files
cd $path_to_nc_files
rm *.clm2.rh0.*.nc
rm *.docn.rs1.*.bin
rm *.cam.r.*.nc
rm *.cam.rs.*.nc
rm *.cpl.r.*.nc
rm *.clm2.rh0.*.nc
rm *.cam.rh3.*.nc
rm *.cice.r.*.nc
rm rpointer.*

cp /home/zarzycki/sewx/INIC/${gridname}_INIC_filter.nc $procdir
cp /home/zarzycki/sewx/SST/sst_1x1.nc $procdir

mv $procdir $outputdir/${yearstr}${monthstr}${daystr}${cyclestr}

date

cd $sewxscriptsdir

if [ $islive -ne 0 ]
then
  ### Still need to figure out how to convert machzone properly
  if [ $machzone -eq -0000 ]
  then
    machzone=0
  elif [ $machzone -eq -0300 ]
  then
    machzone=-300
  elif [ $machzone -eq -0400 ]
  then
    machzone=-400
  elif [ $machzone -eq -0500 ]
  then
    machzone=-500
  elif [ $machzone -eq -0600 ]
  then
    machzone=-600
  elif [ $machzone -eq -0700 ]
  then
    machzone=-700
  elif [ $machzone -eq -0800 ]
  then
    machzone=-800
  elif [ $machzone -eq -0900 ]
  then
    machzone=-900
  else
    echo "Can't figure out machzone, you probably need to manually add it"
    echo "at least until Colin figures out bash arithmetic"
  fi
  
  ## 
  if [ $cyclestr -eq 00 ]
  then
    let "resubhour = 1500 + $machzone"
  elif [ $cyclestr -eq 06 ]
  then
    let "resubhour = 2100 + $machzone"
  elif [ $cyclestr -eq 12 ]
  then
    let "resubhour = 300 + $machzone"
  elif [ $cyclestr -eq 18 ]
  then
    let "resubhour = 900 + $machzone"
  else
    echo "Can't figure out start time"
  fi
  
  if [ $resubhour -lt 0 ]
  then
    let "resubhour = 2400 + $resubhour"
  fi
  let "resubhour = $resubhour/100"
  
  echo "The resub hour is: $resubhour"
  echo "Therefore restart time is: ${resubhour}:30"
  
  #Sed into testshell.csh
  sed -i 's?^#SBATCH --begin.*?#SBATCH --begin='$resubhour':30?' testshell.csh
fi

sbatch notliveshell.csh

exit 0
