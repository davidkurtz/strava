REM getxsd.sh
cd /tmp/strava
wget http://www.topografix.com/GPX/1/0/gpx.xsd --output-document=gpx0.xsd
wget http://www.topografix.com/GPX/1/1/gpx.xsd
wget https://www8.garmin.com/xmlschemas/TrackPointExtensionv1.xsd
ls -l *.xsd
