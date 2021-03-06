#!/bin/bash

# NOTE, need cdsapi Python
# On Cheyenne; run ncar_pylib
# conda activate meteo

## declare an array variable
declare -a months=("01" "02" "03" "04" "05" "06" "07" "08" "09" "10" "11" "12")

STYR=2005
ENYR=2014

## now loop through the above array
for jj in $(seq $STYR $ENYR);
do
  for ii in "${months[@]}"
  do
    echo $jj' '$ii
    python get-data.py "${jj}" "${ii}"
  done
done
