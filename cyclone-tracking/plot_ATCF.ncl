;========================================================
; This script plots ATCF formatting trajectories for NWP
; output
; Colin Zarzycki (czarzycki@psu.edu)
;========================================================
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/shea_util.ncl"
;========================================================
begin

filename=getenv("ATCFFILEMERGE")
yyyymmddhh=getenv("YYYYMMDDHH")

;filename="./fin-atcf/atcf.tempest.2018091000"
;yyyymmddhh="2018091000"

cutwind=0.0
;---Read in file as array of strings so we can parse each line
  lines = asciiread(filename,-1,"string")

  delim = ","

;---Read fields 1, 5 and 9
  _basin  =          str_get_field(lines,1,delim)
  _number_only =          str_get_field(lines,2,delim)
  _number = _basin + _number_only
  _date  =   tointeger(str_get_field(lines,3,delim))
  _modelid  =          str_get_field(lines,5,delim)
  _fctime =  tointeger(str_get_field(lines,6,delim))
  _lat  =          tofloat(str_get_field(lines,7,delim))/10.
  _lon  =          tofloat(str_get_field(lines,8,delim))/10.
  _wind  =          tofloat(str_get_field(lines,9,delim))*0.514444 ; kts to m/s
  _pres  =          tofloat(str_get_field(lines,10,delim))
  _latChar = stringtocharacter(str_strip(str_get_field(lines,7,delim)))
  _lonChar= stringtocharacter(str_strip(str_get_field(lines,8,delim)))
  _latDir = (_latChar(:,4))
  _lonDir = (_lonChar(:,4))
  
  _latDirStr = new(dimsizes(_latDir),"string")
  _lonDirStr = new(dimsizes(_lonDir),"string")
  do i = 0,dimsizes(_latDir)-1
    _latDirStr(i) = chartostring(_latDir(i))
    _lonDirStr(i) = chartostring(_lonDir(i))
  end do
  
  _lat@_FillValue = -999
  _lon@_FillValue = -999
  _lat = where(_latDirStr .eq. "S",-_lat,_lat)
  _lon = where(_lonDirStr .eq. "W",360.-_lon,_lon)

  nstorms=count_unique_values(_number)
  nmodels=count_unique_values(_modelid)
  ntimes=count_unique_values(_fctime)

  print(nstorms+" "+nmodels+" "+ntimes)

  lat = new((/nmodels*nstorms,ntimes/),"float")
  lon = lat
  wind = lat
  pres = lat

uniqNums=get_unique_values(_number)
labelNum=new(dimsizes(uniqNums),"string")
labelLat=new(dimsizes(uniqNums),"float")
labelLon=new(dimsizes(uniqNums),"float")
timeCounter=0
stormCounter=0
THISMODEL=_modelid(0)
THISSTORM=_number(0)
do ii = 0,dimsizes(_lat)-1
  if (ismissing(labelNum(ind(uniqNums.eq.THISSTORM)))) then
    IX = ind(uniqNums.eq.THISSTORM)
    labelNum(IX)=tostring(_number_only(ii))
    labelLat(IX)=_lat(ii)
    labelLon(IX)=_lon(ii)
  end if
  ;print("THISMODEL: "+THISMODEL+"    _modelid(ii) "+_modelid(ii))
  ;print("THISSTORM: "+THISSTORM+"    _number(ii) "+_number(ii))
  if (THISMODEL .eq. _modelid(ii) .and. THISSTORM .eq. _number(ii)) then
    lat(stormCounter,timeCounter) = _lat(ii)
    lon(stormCounter,timeCounter) = _lon(ii)
    wind(stormCounter,timeCounter) = _wind(ii)
    pres(stormCounter,timeCounter) = _pres(ii)
    THISMODEL=_modelid(ii)
    THISSTORM=_number(ii)  
    timeCounter = timeCounter + 1 
  else  ;
    ;print("...... SWITCH")
    timeCounter = 0
    if (THISSTORM .ne. _number(ii) .or. THISMODEL .ne. _modelid(ii))
      stormCounter = stormCounter+1
    end if
    lat(stormCounter,timeCounter) = _lat(ii)
    lon(stormCounter,timeCounter) = _lon(ii)
    wind(stormCounter,timeCounter) = _wind(ii)
    pres(stormCounter,timeCounter) = _pres(ii)
    THISMODEL=_modelid(ii)
    THISSTORM=_number(ii)   
  end if
end do

nstorms = nstorms*nmodels

print("Beginning plot sequence")
wks  = gsn_open_wks("png","enstraj."+yyyymmddhh)

numpanels=4
map = new(numpanels,graphic)
dum = new((/numpanels,nstorms,ntimes/),graphic)
text = new((/numpanels,dimsizes(uniqNums)/),graphic)

res  = True
res@gsnDraw    = False
res@gsnFrame   = False
res@gsnMaximize = True
res@mpFillOn             = True              ; turn off gray continents
res@mpLandFillColor = "Tan"
res@mpOceanFillColor = "Black"
res@mpOutlineOn = True
res@mpInlandWaterFillColor = res@mpOceanFillColor
res@mpGreatCircleLinesOn = True
res@mpOutlineBoundarySets=""
 
do zz = 0,3
delete(res@mpOutlineBoundarySets)
if (zz .eq. 0)  ;atlantic
  res@mpMinLatF             = 10
  res@mpMaxLatF             = 45
  res@mpMinLonF             = 260
  res@mpMaxLonF             = 350
  res@mpOutlineBoundarySets = "USStates" 
else if (zz .eq. 1) ; epac
  res@mpMinLatF  = 10
  res@mpMaxLatF = 35
  res@mpMinLonF  = -165
  res@mpMaxLonF = -95
else if (zz .eq. 2) ; epac
  res@mpMinLatF  = 10
  res@mpMaxLatF = 45
  res@mpMinLonF  = 105
  res@mpMaxLonF = 195
else if (zz .eq. 3)
  res@mpMinLatF             = 0
  res@mpMaxLatF             = 65
  res@mpMinLonF             = 50
  res@mpMaxLonF             = 350
else
  print("invalid basin")
end if
end if
end if
end if

map(zz) = gsn_csm_map_ce(wks,res)

gsn_define_colormap(wks,"rainbow+white+gray")
  polyres               = True          ; poly marker mods desired 
  polyres@gsMarkerIndex = 1            ; choose circle as polymarker
  lineres = True

do i = 0,nstorms-1
do j = 0,ntimes-1

thisWind=wind(i,j)

;lineres@gsLineThicknessF = 8.0
; We need to use thinner lines for the global map
  ;linethicknesses = (/0.5,1.0,1.3,1.9,2.3,2.6/)
  linethicknesses = (/0.5,1.0,1.0,1.0,1.0,1.0/)
  linethicknesses = linethicknesses*4.5

if (.not.ismissing(thisWind))

;  polyres@gsMarkerSizeF = 2.0           ; select size to avoid streaking
  if (thisWind .lt. 17)
    polyres@gsMarkerColor = (/"lightblue"/)
    lineres@gsLineColor = (/"lightblue"/)
    lineres@gsLineThicknessF = linethicknesses(0)
  else if (thisWind .ge. 17 .and. thisWind .lt. 33)
    polyres@gsMarkerColor = (/"green3"/)
    lineres@gsLineColor = (/"green3"/)
    lineres@gsLineThicknessF = linethicknesses(1)
  else if (thisWind .ge. 33 .and. thisWind .lt. 43)
    polyres@gsMarkerColor = (/"yellow2"/)
    lineres@gsLineColor = (/"yellow2"/)
    lineres@gsLineThicknessF = linethicknesses(2)
  else if (thisWind .ge. 43 .and. thisWind .lt. 49)
    polyres@gsMarkerColor = (/"orange"/)
    lineres@gsLineColor = (/"orange"/)
    lineres@gsLineThicknessF = linethicknesses(3)
  else if (thisWind .ge. 49 .and. thisWind .lt. 58)
    polyres@gsMarkerColor = (/"darkorange3"/)
    lineres@gsLineColor = (/"darkorange3"/)
    lineres@gsLineThicknessF  = linethicknesses(4)
  else
    polyres@gsMarkerColor = (/"red"/) 
    lineres@gsLineColor = (/"red"/)
    lineres@gsLineThicknessF  = linethicknesses(5)
  end if
  end if
  end if
  end if
  end if
  
  if (j .ne. 0) then
    if(thisWind .ge. cutwind) then
      dum(zz,i,j) = gsn_add_polyline(wks,map(zz),(/lon(i,j),lon(i,j-1)/),(/lat(i,j),lat(i,j-1)/),lineres)
    end if
  end if
  
end if

end do



end do

do jj = 0,dimsizes(uniqNums)-1
  txres = True         
  txres@txFontColor = "white"
  txres@txFontHeightF = 0.015             ; Set the font height
  txres@amJust = "TopLeft"                   
  text(zz,jj) = gsn_add_text(wks,map(zz),labelNum(jj),labelLon(jj)+0.5,labelLat(jj)-0.5,txres)
end do

; if we are doing a varres grid, let's push an outline of the atl30x4 grid
;if (modelgrid .eq. "vr") then
;  map = plot_outline_fcn(wks,map,"black",3.0)
;end if

end do

;******************
; Plot a legend   *
;******************

lgres                    = True

lgres@lgAutoManage       = False

lgres@vpWidthF           = 0.08       ; was 0.08        ; width of legend (NDC)
lgres@vpHeightF          = 0.12       ; was 0.08        ; height of legend (NDC)
; lgres@lgBottomMarginF    = 0.17     ; was 0.25

lgres@lgPerimFill        = 0                     ; Use solid fill (0) instead of the default hollow fill
lgres@lgPerimFillColor   = "Background"

;lgres@lgOrientation = "Horizontal"

; lgres@lgBoxMajorExtentF  = 0.4
lgres@lgBoxMinorExtentF  = 0.2	; controls how wide the box holding the legend items (lines and markers) can be in relation to legend

; lgres@lgBoxBackground    = "PaleTurquoise3"

lgres@lgMonoItemType        = False                 ; indicates that we wish to set the item types individually
lgres@lgMonoMarkerIndex     = False
lgres@lgMonoLineThickness   = False
lgres@lgMonoMarkerThickness = False
lgres@lgMonoMarkerSize      = False

;lgres@lgLabelFont             = 0
lgres@lgLabelFontHeightF      = 0.07
lgres@lgLabelFontAspectF      = 1.5
lgres@lgLabelConstantSpacingF = 0.0

legendType = "Markers"
markerSize = .008
markerIndex = 16

if (cutwind .eq. 0) then
lgres@lgItemCount        = 6
;lgres@lgLineDashSegLenF  = 0.8
lgres@lgItemTypes        = (/"Markers","Markers","Markers","Markers","Markers","Markers"/)
lgres@lgMarkerIndexes    = (/      16,      16,      16,      16,      16,      16/)
lgres@lgMarkerThicknesses  = (/    markerSize,    markerSize,    markerSize,    markerSize,    markerSize,    markerSize/)
lgres@lgMarkerColors       = (/ "red",     "darkorange3",   "orange",  "yellow",   "green",    "blue"    /) ; colors for legend lines
;lgres@lgDashIndexes      = (/      0,          0,          0,         0,               0,      0      /) ; dash indexes
legend_labels = (/"Cat. 4/5","Cat. 3","Cat. 2",\
               "Cat. 1","TS","TD"/)
else if (cutwind .eq. 17) then
  lgres@lgItemCount        = 5
  lgres@lgItemTypes        = (/legendType,legendType,legendType,legendType,legendType/)
  lgres@lgMarkerIndexes    = (/markerIndex,markerIndex,markerIndex,markerIndex,markerIndex/)
  lgres@lgMarkerThicknesses  = (/    markerSize,    markerSize,    markerSize,    markerSize,    markerSize/)
  lgres@lgMarkerColors       = (/ "red",     "darkorange3",   "orange",  "yellow2",   "green3" /) ; colors for legend lines
  legend_labels = (/"Category 4/5","Category 3","Category 2",\
                 "Category 1","Tropical Storm"/)
else
end if
end if


legend = gsn_create_legend(wks,lgres@lgItemCount,legend_labels,lgres)

amres = True

amres@amJust="TopLeft"
amres@amParallelPosF   = -.49		    ; move legend to the right
amres@amOrthogonalPosF = -.49             ; move the legend down


annoid1 = gsn_add_annotation(map(3),legend,amres)   ; add legend to plot
  
print("Drawing plot")

resP = True
resP@amJust           = "TopRight"
resP@gsnPanelFigureStringsFontHeightF = 0.027
gsn_panel(wks,map,(/4,1/),resP)             ; now draw as one plot
  
end
