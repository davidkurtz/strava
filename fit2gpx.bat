cd C:\Users\david\vagrant\vagrant-oracle19c9\files

for %i in (*.fit.gz) do "C:\Program Files\GnuWin\bin\gzip" -fd %i
for %i in (*.fit) do "C:\Program Files (x86)\GPSBabel\GPSBabel.exe" -i garmin_fit -f "%i" -o gpx -F "%~ni".gpx --recoverymode
