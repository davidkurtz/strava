#load_shapes.sh

function echodo {
  echo "$*"
  time $*
}

function shp_load {
  echo $0:$*

  if [ $# -lt 1 ] 
   then
    echo "Usage: <.shp file> [<srid> [<table_name>]]"
    echo "default table_name = base of .shp filename"
    echo "default srid = 4326"
    exit
  fi

#get shapefile name and check it exists   
  if [ $# -ge 1 ]
   then
    file=$1
    base=`basename $file .shp`
    dir=`dirname $file`
     
    if [ -r ${dir}/${base}.shp ]
     then
      shift
    else
      echo "Cannot read ${dir}/${base}.shp"
      exit
    fi
  fi

#srid override and determine geom column name
  if [ $# -ge 1 ]
   then 
    srid=$1
    col="geom_${srid}"
    shift
  else
    srid=4326
    col="geom"
  fi
  echo "srid=\"${srid}\""
  echo "col=\"${col}\""

#table name override
  if [ $# -ge 1 ]
   then
    table=$1
    shift
  else
    table=$base
  fi

  cd $dir
  pwd
  export clpath=$ORACLE_HOME/suptools/tfa/release/tfa_home/jlib/ojdbc5.jar:$ORACLE_HOME/md/jlib/sdoutl.jar:$ORACLE_HOME/md/jlib/sdoapi.jar
  echodo "java -cp $clpath oracle.spatial.util.SampleShapefileToJGeomFeature -h oracle-database.local -p 1521 -sn oracle_pdb -u strava -d strava -t $table -f $base -r $srid -g ${col}"
}

clear
#set -x

#shp_load /tmp/strava/ne_10m_admin_0_sovereignty.shp
#shp_load /tmp/strava/ne_10m_admin_0_map_units
#shp_load /tmp/strava/ne_10m_admin_0_map_subunits

#shp_load /tmp/strava/Areas_of_Outstanding_Natural_Beauty__England____Natural_England.shp 27700 AONB

#shp_load /tmp/strava/Data/GB/county_region.shp 27700
#shp_load /tmp/strava/Data/GB/district_borough_unitary_region.shp 27700
#shp_load /tmp/strava/Data/GB/district_borough_unitary_ward_region.shp 27700
#shp_load /tmp/strava/Data/GB/parish_region.shp 27700
#shp_load /tmp/strava/Data/Supplementary_Ceremonial/Boundary-line-ceremonial-counties_region.shp 27700
#shp_load /tmp/strava/Data/Wales/community_ward_region.shp 27700
#shp_load /tmp/strava/pub_commcnc.shp 27700

#shp_load /tmp/strava/AUT_adm1.shp 
#shp_load /tmp/strava/AUT_adm1.shp 

#BEL
#CHE
#DEU
#ESP

#shp_load /tmp/strava/FRA_adm1.shp 
#shp_load /tmp/strava/FRA_adm2.shp 
#shp_load /tmp/strava/FRA_adm3.shp 
#shp_load /tmp/strava/FRA_adm4.shp 
#shp_load /tmp/strava/FRA_adm5.shp 

#shp_load /tmp/strava/IRL_adm1.shp 

#shp_load /tmp/strava/NLD_adm1.shp 
#shp_load /tmp/strava/NLD_adm2.shp 

#shp_load /tmp/strava/USA_adm1.shp 
#shp_load /tmp/strava/USA_adm2.shp 

#