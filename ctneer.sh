#!/bin/bash
# Combined dab.conf and script to create virtual machine
# 
# Create dabfile
# Start with dab.conf
#
# Finish with 
# %EXEC
# ... script
# %PUBLISH
# [EOF]
# This will create dab.conf
# and will execute everything after dab.conf
# if optional %PUBLISH exists it will copy template to PVE cache

TEMPLATE_CACHE=/var/lib/vz/template/cache

DOTEMPLATE=0
OVERRIDE_NAME=
DODEPLOY=0
DOSTART=0
DABFILE=dabfile
DOEXTRACT=0

while [[ $# > 0 ]]; do
    key="$1"
    case $key in
    -t)
    DOTEMPLATE=1
    ;;
    -n)
    OVERRIDE_NAME="$2"
    shift # past argument
    ;;
    -c)
    DODEPLOY=1
    shift
    break;
    ;;
    -f)
    DABFILE=$2
    ;;
    -s)
    DOSTART=1
    ;;
    -e)
    DOEXTRACT=1
    ;;
    -h|--help|-?)
    echo "Usage:"
    echo "$0 [options]"
    echo " -f <dabfile>		- use specified dabfile instead of ./dabfile"
    echo " -e 			- prepare dab.conf and dab.script and quit"
    echo " -t 			- create template (force to create if already present)"
    echo " -n <name> 		- override template name Template: ... name in dabfile"
    echo " -c <...options...>	- deploy virtual machine (see man pct create for options) MUST BE LAST OPTION"
    echo " -s 			- start it"
    echo " "
    echo "If no options specified, will create template if not exists"
    echo "in /var/lib/vz/cache/"
    exit 0
    ;;
    *)
    # unknown option
    echo "Error: unknown option $1"
    exit 1
    ;;
    esac
    shift # past argument or value
done

if [ ! -f dabfile ]; then
    echo Error: $DABFILE not found
    exit 1
fi

# Generate unique ID
STAMP=`date +%Y%m%d%H%M%s`
DIR=/tmp

# Explode dabfile into dab.conf
awk '/^\%EXEC/{exit};1' $DABFILE > $DIR/$STAMP.conf
if [ "$?" != "0" ]; then
    echo Error: failed to extract dab.conf!
fi

# Any anything possible dab.script
awk '/^\%EXEC/{flag=1;next}/^\%PUBLISH/{flag=0}flag' dabfile > $DIR/$STAMP.script
if [ "$?" != "0" ]; then
    echo Error: failed to extract dab script!
fi

# Parse dab.conf into environment variables
sed -re "s/([a-zA-Z0-9]+)[ ]*:[ ]*(.*)$/dab_\1=\"\2\"/g;s/^[ ]+.*//g" $DIR/$STAMP.conf > $DIR/$STAMP.env
source $DIR/$STAMP.env

# Parse publish and deploy markers
ISPUBLISH=`awk '/^\%PUBLISH/' dabfile`

if [ "$ISPUBLISH" != "" ]; then
    ISPUBLISH=1
else
    ISPUBLISH=0
fi


if [ "$dab_OS" == "" ]; then
    dab_OS=debian-8.0
fi

if [ "$dab_Architecture" == "" ]; then
    dab_Architecture=amd64
fi


HASH=`sha1sum $DABFILE | cut -d" " -f1`
# Add hash of source dabfile (to avoid recreating template)
if [ "$dab_TemplateHash" == "" ]; then
    dab_TemplateHash=$HASH
    echo "TemplateHash: $HASH" >$DIR/$STAMP\_prepend.conf
    cat $DIR/$STAMP.conf >>$DIR/$STAMP\_prepend.conf
    mv $DIR/$STAMP\_prepend.conf $DIR/$STAMP.conf
fi

DAB_FILE=$dab_OS-$dab_Name\_$dab_Version\_$dab_Architecture
if [ "$dab_Template" = "" ]; then
    dab_Template=$DAB_FILE
    echo "Template: $dab_Template" >$DIR/$STAMP\_prepend.conf
    cat $DIR/$STAMP.conf >>$DIR/$STAMP\_prepend.conf
    mv $DIR/$STAMP\_prepend.conf $DIR/$STAMP.conf
fi

# Add CacheDir: if not set (def to $HOME/.dab-cache)
if [ "$dab_CacheDir" == "" ]; then
    echo "CacheDir: $HOME/.dab-cache" >$DIR/$STAMP\_prepend.conf
    cat $DIR/$STAMP.conf >>$DIR/$STAMP\_prepend.conf
    mv $DIR/$STAMP\_prepend.conf $DIR/$STAMP.conf
    dab_CacheDir=$HOME/.dab-cache
fi

# Our target template name
if [[ "$TEMPLATE_NAME" == "" ]]; then
    if [[ "$dab_Template" != "" ]]; then
	TEMPLATE_NAME=$dab_Template
    else
	TEMPLATE_NAME=$DAB_FILE
    fi
fi
function atexit_func {
    rm $DIR/$STAMP.env
    rm $DIR/$STAMP.conf
    rm $DIR/$STAMP.script

    if [ "$DOTEMPLATE" == "1" ]; then
	dab clean
	rm ./dab.conf
    fi
}

trap "atexit_func" EXIT

# Extract and do nothing
if [[ "$DOEXTRACT" == "1" ]]; then
    cp $DIR/$STAMP.conf dab.conf
    cp $DIR/$STAMP.script dab.script
    exit 0
fi

# Check template already in cache
TEMPLATE_FOUND=0
if [[ -f $TEMPLATE_CACHE/$TEMPLATE_NAME.tar.gz ]]; then
    if [ -f $TEMPLATE_CACHE/$TEMPLATE_NAME.hash ]; then
	THASH=`cat $TEMPLATE_CACHE/$TEMPLATE_NAME.hash`
    fi
    if [[ "$THASH" == "$HASH" ]]; then
	TEMPLATE_FOUND=1
    else
        THASH=`tar -xOzf $TEMPLATE_CACHE/$TEMPLATE_NAME.tar.gz ./etc/appliance.hash`
	if [[ "$THASH" == "$HASH" ]]; then
	    TEMPLATE_FOUND=1
	    echo "Caching hash $HASH into $TEMPLATE_CACHE/$TEMPLATE_NAME.hash"
	    echo $HASH >$TEMPLATE_CACHE/$TEMPLATE_NAME.hash
	else
    	    echo "Template hash mismatch ($HASH -> $THASH, will recreate template)"
        fi
    fi
fi

# Check or force create template
if [[ "$DOTEMPLATE" == "1" || "$TEMPLATE_FOUND" == 0 ]]; then
    echo "Creating template $TEMPLATE_NAME (dab $DAB_FILE.tar.gz)..."
    DOTEMPLATE=1
    cp $DIR/$STAMP.conf dab.conf
    /bin/bash $DIR/$STAMP.script
    ERR=$?
    if [ "$ERR" != "0" ]; then
	echo Error: %EXEC finished with error $ERR
	exit 1
    fi

    if [ -f $DAB_FILE.tar.gz ]; then
	# Put hash inside archive
	gzip -d $DAB_FILE.tar.gz
	mkdir etc
	echo $HASH >etc/appliance.hash
	tar rf $DAB_FILE.tar ./etc/appliance.hash
	gzip $DAB_FILE.tar
	rm -Rf etc
	# Publish template
	mv $DAB_FILE.tar.gz $TEMPLATE_CACHE/$TEMPLATE_NAME.tar.gz
	if [ "$?" != "0" ]; then
	    echo "Error: cant move $TEMPLATE_NAME.tar.gz to $TEMPLATE_CACHE"
	    exit 2
	fi

	# Add cached HASH
	echo $HASH >$TEMPLATE_CACHE/$TEMPLATE_NAME.hash
    else
	echo "Error: $DAB_FILE.tar.gz not created! %EXEC is invalid (does you issue dab finalize?)"
	exit 2
    fi
else 
	echo "Template $TEMPLATE_NAME up-to-date with $DABFILE"
fi

echo Using template: $TEMPLATE_NAME

if [[ "$DODEPLOY" == "1" ]]; then
    LASTVM=` pct list | cut -d" " -f1 | sort -g -r | head -n 1`
    LASTVM=`expr $LASTVM + 1`
    echo "Creating vm $LASTVM $TEMPLATE_CACHE/$TEMPLATE_NAME.tar.gz $*"
    pct create $LASTVM $TEMPLATE_CACHE/$TEMPLATE_NAME.tar.gz $*
    ERR=$?
    if [[ "$ERR" != "0" ]]; then
	echo "Error: failed to exec pct create, err $ERR"
	exit 1
    fi

    echo "Your VMID is $LASTVM"
fi

if [[ "$DOSTART" == "1" ]]; then
    if [[ "$LASTVM" != "" ]]; then
	echo "Starting $LASTVM"
	pct start $LASTVM
    fi
fi
