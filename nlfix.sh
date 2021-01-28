#nlfix.sh
/usr/bin/gawk -v RS='"' 'NR % 2 == 0 { gsub(/\n/, "") } { printf("%s%s", $0, RT) }' $*
