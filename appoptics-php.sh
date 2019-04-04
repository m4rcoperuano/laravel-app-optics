#! /bin/sh -e

SERVICE_KEY=
EXTENSION_DIR=
CONFIG_DIR_APACHE=
CONFIG_DIR_FPM=
CONFIG_DIR_CLI=
THREAD_SAFETY=
API=
TMP_DIR=/tmp/appoptics-php
DOWNLOAD_URL="https://files.appoptics.com/php"
VERSION=latest
MODE=install
DEBUG=no

test_write_access() {
    set +e
    WRITE_LOCATION=$1
    if [ -z "$WRITE_LOCATION" ]; then
        echo "Empty location given."
        exit 1
    fi
    if [ -d $WRITE_LOCATION ]; then
        touch $WRITE_LOCATION/tmp_write 1>/dev/null 2>&1
        if [ $? != 0 ]; then
            echo "No write access to $WRITE_LOCATION. Run script as root."
            exit 1
        fi
        rm -f $WRITE_LOCATION/tmp_write
    elif [ -f $WRITE_LOCATION ]; then
        touch $WRITE_LOCATION 1>/dev/null 2>&1
        if [ $? != 0 ]; then
            echo "No write access to $WRITE_LOCATION. Run script as root."
            exit 1
        fi
    else
        echo "$WRITE_LOCATION not found."
        exit 1
    fi
    set -e
}

tidy_up() {
    rm -rf $TMP_DIR
}

check_sha256sum_installed() {
    # check if sha256sum is installed
    if [ -z "$(which sha256sum)" ]; then
        echo "Need sha256sum to verify checksums."
        exit 1
    fi
}

##############################################################################

print_usage_and_exit() {
    echo "Usage: $0 --service-key=<KEY> [--mode=<install|uninstall>] [--extension-dir=<DIR>] [--ini-dir=<DIR>] [--thread-safety=<TS|NTS>] [--api=<API>] [--version=<VERSION>] [--url=<URL>]"
    echo "--service-key: unique service identifier"
    echo "--mode: install or uninstall the PHP agent (optional, default: install)"
    echo "--extension-dir: Extension directory (optional, will attempt to detect automatically if not set)"
    echo "--ini-dir: INI directory (optional, will attempt to detect automatically if not set)"
    echo "--thread-safety: install thread-safe (TS) or non-thread-safe (NTS) version (optional, will attempt to detect automatically if not set)"
    echo "--api: install PHP extension version (e.g. 20170718, optional, will attempt to detect automatically if not set)"
    echo "--version: version to install (optional, default: latest)"
    echo "--url: URL to get the PHP agent from (optional, default: https://files.appoptics.com/php)"
    exit 1
}

for i in "$@"; do
    if [ -n "$i" ]; then
        case $i in
            --service-key=*)
            SERVICE_KEY=$(echo $i | awk -F= {'print $2'})
            ;;
            --mode=*)
            MODE=$(echo $i | awk -F= {'print $2'})
            ;;
            --extension-dir=*)
            EXTENSION_DIR=$(echo $i | awk -F= {'print $2'})
            test_write_access $EXTENSION_DIR
            ;;
            --ini-dir=*)
            CONFIG_DIR_APACHE=$(echo $i | awk -F= {'print $2'})
            CONFIG_DIR_FPM=$CONFIG_DIR_APACHE
            CONFIG_DIR_CLI=$CONFIG_DIR_APACHE
            test_write_access $CONFIG_DIR_APACHE
            ;;
            --thread-safety=*)
            THREAD_SAFETY=$(echo $i | awk -F= {'print $2'})
            ;;
            --api=*)
            API=$(echo $i | awk -F= {'print $2'})
            ;;
            --version=*)
            VERSION=$(echo $i | awk -F= {'print $2'})
            ;;
            --url=*)
            DOWNLOAD_URL=$(echo $i | awk -F= {'print $2'})
            ;;
            --debug)
            DEBUG=yes
            ;;
            *)
            echo "Unknown or incomplete option: $i"
            print_usage_and_exit
            ;;
        esac
    fi
done

if [ "$MODE" != "install" ] && [ "$MODE" != "uninstall" ]; then
    echo "Unknown mode $MODE (should be either install or uninstall)."
    print_usage_and_exit
fi
if [ "$MODE" != "uninstall" ] && [ -z "$SERVICE_KEY" ]; then
    echo "Please pass in a service key via the --service-key option."
    print_usage_and_exit
fi
if [ -z "$VERSION" ]; then
    echo "No version given with --version."
    print_usage_and_exit
fi
if [ -z "$DOWNLOAD_URL" ]; then
    echo "No URL given with --url."
    print_usage_and_exit
fi

##############################################################################

# check if php cli is installed
if [ -z "$(which php)" ]; then
    echo "Please install PHP CLI before running this script.";
    exit 1
fi

# find extension dir and see if we have write access
if [ -z "$EXTENSION_DIR" ]; then
    EXTENSION_DIR=$(php -i 2>/dev/null | grep "^extension_dir" | awk {'print $5'})
    if [ -n "$EXTENSION_DIR" ]; then
        test_write_access $EXTENSION_DIR
    else
        echo "Could not determine PHP Extension dir."
        exit 1
    fi
fi

# find config dir/file and see if we have write access
if [ -z "$CONFIG_DIR_APACHE" ] && [ -z "$CONFIG_DIR_FPM" ] && [ -z "$CONFIG_DIR_CLI" ]; then
    for ini_path in /etc/php5 /etc/php7 /etc/php/[57].*; do
        if [ -e "$ini_path/apache2/conf.d" ]; then
            CONFIG_DIR_APACHE=$ini_path/apache2/conf.d
            test_write_access $CONFIG_DIR_APACHE
        fi
        if [ -e "$ini_path/fpm/conf.d" ]; then
            CONFIG_DIR_FPM=$ini_path/fpm/conf.d
            test_write_access $CONFIG_DIR_FPM
        fi
        if [ -e "$ini_path/cli/conf.d" ]; then
            CONFIG_DIR_CLI=$ini_path/cli/conf.d
            test_write_access $CONFIG_DIR_CLI
        fi
    done

    if [ -z "$CONFIG_DIR_CLI" ]; then
        CONFIG_DIR_CLI=$(php -i 2>/dev/null | grep "^Scan this dir for additional .ini files" | awk {'print $9'})
        if [ -z "$CONFIG_DIR_CLI" ] || [ "$CONFIG_DIR_CLI" = "(none)" ]; then
            CONFIG_DIR_CLI=
            CONFIG_FILE_CLI=$(php -i 2>/dev/null | grep "^Loaded Configuration File" | awk {'print $5'})
            echo "Could not determine the directory for additional PHP .ini files."
        else
            test_write_access $CONFIG_DIR_CLI
        fi
    fi
fi

# get PHP extension
if [ -z "$API" ]; then
    API=$(php -i 2>/dev/null | grep "^PHP Extension => " | awk {'print $4'})
    if [ -z "$API" ]; then
        echo "Could not determine PHP extension."
        exit 1
    fi
fi

# check if Thread Safety is enabled
ZTS=
if [ -n "$THREAD_SAFETY" ]; then
    if [ "$THREAD_SAFETY" = "TS" ]; then
        ZTS="+zts"
    fi
elif [ -n "$(php -i 2>/dev/null | grep "^Thread Safety => enabled")" ]; then
    ZTS="+zts"
fi

# get architecture
ARCH=$(uname -m)
case "$ARCH" in *86) ARCH=i686; esac

# we dropped support for 32-bit systems
if [ "$ARCH" = "i686" ]; then
    echo "32-bit system are currently not supported."
    exit 1
fi

# check if this is a debug build
if [ -n "$(php -i 2>/dev/null | grep "^Debug Build => yes")" ]; then
    echo "PHP debug builds are not supported."
    exit 1
fi

# check if we are on Alpine Linux
ALPINE=no
if [ -f /etc/alpine-release ]; then
    MAJOR_MINOR=$(cat /etc/alpine-release | sed 's/^\([0-9]\+\)\.\([0-9]\+\).*/\1\2/')
    if [ $MAJOR_MINOR -ge 39 ]; then
        ALPINE=openssl
    else
        ALPINE=libressl
    fi
fi

if [ "$DEBUG" = "yes" ]; then
    echo "EXTENSION_DIR = $EXTENSION_DIR"
    echo "CONFIG_DIR_APACHE = $CONFIG_DIR_APACHE"
    echo "CONFIG_DIR_FPM = $CONFIG_DIR_FPM"
    echo "CONFIG_DIR_CLI = $CONFIG_DIR_CLI"
    echo "CONFIG_FILE_CLI = $CONFIG_FILE_CLI"
    echo "API = $API"
    echo "ZTS = $ZTS"
    echo "ARCH = $ARCH"
    echo "ALPINE = $ALPINE"
fi

##############################################################################

if [ "$ALPINE" = "openssl" ]; then
    SO_FILE="appoptics-php-${API}${ZTS}-alpine-${ARCH}.so"
elif [ "$ALPINE" = "libressl" ]; then
    SO_FILE="appoptics-php-${API}${ZTS}-alpine-libressl-${ARCH}.so"
else
    SO_FILE="appoptics-php-${API}${ZTS}-${ARCH}.so"
fi
SO_FILE_ENCODED="$(echo $SO_FILE | sed 's/+/%2B/g')"
SO_FILE_INSTALLED="appoptics.so"
INI_FILE="appoptics.ini"

# uninstall if requested
if [ "$MODE" = "uninstall" ]; then
    NOT_INSTALLED=true
    if [ -f "$EXTENSION_DIR/$SO_FILE_INSTALLED" ]; then
        rm -f $EXTENSION_DIR/$SO_FILE_INSTALLED
        NOT_INSTALLED=false
    fi
    if [ -n "$CONFIG_DIR_APACHE" ]; then
        rm -f $CONFIG_DIR_APACHE/$INI_FILE*
        NOT_INSTALLED=false
    fi
    if [ -n "$CONFIG_DIR_FPM" ]; then
        rm -f $CONFIG_DIR_FPM/$INI_FILE*
        NOT_INSTALLED=false
    fi
    if [ -n "$CONFIG_DIR_CLI" ]; then
        rm -f $CONFIG_DIR_CLI/$INI_FILE*
        NOT_INSTALLED=false
    fi
    if [ -n "$CONFIG_FILE_CLI" ]; then
        if [ -n "$(egrep '^ *appoptics.service_key *=' $CONFIG_FILE_CLI)" ]; then
            echo "Please manually remove appoptics specific configuration from $CONFIG_FILE_CLI"
            NOT_INSTALLED=false
        fi
    fi
    
    if [ "$NOT_INSTALLED" = "true" ]; then
        echo "No PHP agent installed."
    else
        echo "Done uninstalling the PHP agent."
    fi
    exit 0
fi

# create new directory under /tmp
rm -rf $TMP_DIR
mkdir $TMP_DIR

# check if we have a tarball in which case we use the files from the tarball instead of downloading them from the internet
TARBALL="appoptics-php.tar.gz"
if [ -f $TARBALL ]; then
    echo "Using local tarball appoptics-php.tar.gz ..."
    TARBALL_DIR=/tmp/appoptics-php-tar
    rm -rf $TARBALL_DIR
    mkdir $TARBALL_DIR
    tar xf $TARBALL -C $TARBALL_DIR
    
    cp $TARBALL_DIR/$SO_FILE.sha256 $TMP_DIR/$SO_FILE.sha256
    if [ -f "$EXTENSION_DIR/$SO_FILE_INSTALLED" ]; then
        check_sha256sum_installed
        SHA256=$(sha256sum $EXTENSION_DIR/$SO_FILE_INSTALLED | awk {'print $1'})
        if [ "$(cat $TMP_DIR/$SO_FILE.sha256)" = "$SHA256" ]; then
            echo "Installed agent is already the latest."
            rm -rf $TARBALL_DIR
            tidy_up
            exit 0
        fi
    fi
    
    cp $TARBALL_DIR/$SO_FILE $TMP_DIR/$SO_FILE
    cp $TARBALL_DIR/$INI_FILE $TMP_DIR/$INI_FILE
    cp $TARBALL_DIR/VERSION $TMP_DIR/VERSION
    rm -rf $TARBALL_DIR
else
    echo "Downloading from $DOWNLOAD_URL/$VERSION ..."
    # check if wget or curl is installed
    if [ -z "$(which wget)" ]; then
        if [ -z "$(which curl)" ]; then
            FETCH_CMD=
        else
            FETCH_CMD="curl -f -m 10 --retry 1 -o"
        fi
    else
        FETCH_CMD="wget --timeout=10 --tries=1 -O"
    fi
    if [ -z "$FETCH_CMD" ]; then
        echo "Need either wget or curl installed."
        exit 1
    fi
    
    # download files
    echo "$DOWNLOAD_URL/$VERSION/$SO_FILE_ENCODED.sha256 -> $TMP_DIR/$SO_FILE.sha256"
    F_RES="$($FETCH_CMD $TMP_DIR/$SO_FILE.sha256 $DOWNLOAD_URL/$VERSION/$SO_FILE_ENCODED.sha256 2>&1 | egrep "404 Not Found|403[:]? Forbidden|error: 404" || true)"
    if [ -n "$F_RES" ]; then
        echo "The version '$VERSION' or the file '$SO_FILE.sha256' was not found."
        tidy_up
        exit 1
    fi
    if [ ! -e "$TMP_DIR/$SO_FILE.sha256" ]; then
        echo "Could not download $DOWNLOAD_URL/$VERSION/$SO_FILE.sha256."
        tidy_up
        exit 1
    fi
    if [ -f "$EXTENSION_DIR/$SO_FILE_INSTALLED" ]; then
        check_sha256sum_installed
        SHA256=$(sha256sum $EXTENSION_DIR/$SO_FILE_INSTALLED | awk {'print $1'})
        if [ "$(cat $TMP_DIR/$SO_FILE.sha256)" = "$SHA256" ]; then
            echo "Installed agent is already on this version."
            tidy_up
            exit 0
        fi
    fi
    
    echo "$DOWNLOAD_URL/$VERSION/$SO_FILE_ENCODED -> $TMP_DIR/$SO_FILE"
    $FETCH_CMD $TMP_DIR/$SO_FILE $DOWNLOAD_URL/$VERSION/$SO_FILE_ENCODED >/dev/null 2>&1
    echo "$DOWNLOAD_URL/$VERSION/$INI_FILE -> $TMP_DIR/$INI_FILE"
    $FETCH_CMD $TMP_DIR/$INI_FILE $DOWNLOAD_URL/$VERSION/$INI_FILE >/dev/null 2>&1
    echo "$DOWNLOAD_URL/$VERSION/VERSION -> $TMP_DIR/VERSION"
    $FETCH_CMD $TMP_DIR/VERSION $DOWNLOAD_URL/$VERSION/VERSION >/dev/null 2>&1
    
    # verify checksum
    if [ -f $TMP_DIR/$SO_FILE ] || [ -f $TMP_DIR/$SO_FILE.sha256 ]; then
        check_sha256sum_installed
        SHA256=$(sha256sum $TMP_DIR/$SO_FILE | awk {'print $1'})
        if [ "$(cat $TMP_DIR/$SO_FILE.sha256)" != "$SHA256" ]; then
            echo "SHA256 checksum of file $TMP_DIR/$SO_FILE doesn't match:"
            echo "Expected: $(cat $TMP_DIR/$SO_FILE.sha256)"
            echo "Actual:   $SHA256"
            exit 1
        fi
    else
        echo "$TMP_DIR/$SO_FILE and/or $TMP_DIR/$SO_FILE.sha256 not found."
        exit 1
    fi
fi

##############################################################################

REAL_VERSION=$(cat $TMP_DIR/VERSION)

# copy extension
if [ -n "$EXTENSION_DIR" ] && [ -d "$EXTENSION_DIR" ]; then
    echo "Copying $TMP_DIR/$SO_FILE ($REAL_VERSION) to $EXTENSION_DIR/$SO_FILE_INSTALLED ..."
    cp $TMP_DIR/$SO_FILE $EXTENSION_DIR/$SO_FILE_INSTALLED
else
    echo "Extension dir not found"
    exit 1
fi

# prepare INI file
if [ ! -f $TMP_DIR/$INI_FILE ]; then
    echo "$TMP_DIR/$INI_FILE not found"
    exit 1
else
    # write service key to ini file
    sed -i 's/^\( *appoptics.service_key *=\).*/\1 '$SERVICE_KEY'/g' $TMP_DIR/$INI_FILE
fi
if [ -z "$CONFIG_DIR_APACHE" ] || [ ! -d "$CONFIG_DIR_APACHE" ]; then
    if [ -z "$CONFIG_DIR_FPM" ] || [ ! -d "$CONFIG_DIR_FPM" ]; then
        if [ -z "$CONFIG_DIR_CLI" ] || [ ! -d "$CONFIG_DIR_CLI" ]; then
            if [ -z "$CONFIG_FILE_CLI" ] || [ ! -f "$CONFIG_FILE_CLI" ]; then
                echo "No valid config location set."
                exit 1
            fi
        fi
    fi
fi

# save checksum of default ini file (needed for being able to tell if config file has been changed)
# this needs to happend AFTER the service key has been written to the file
check_sha256sum_installed
sha256sum $TMP_DIR/$INI_FILE | awk {'print $1'} > $TMP_DIR/$INI_FILE.sha256

# check if config file(s) need to be updated
CONFIG_APACHE_UPDATE=no
if [ -n "$CONFIG_DIR_APACHE" ] && [ -d "$CONFIG_DIR_APACHE" ]; then
    if [ -f "$CONFIG_DIR_APACHE/$INI_FILE" ] && [ -f "$CONFIG_DIR_APACHE/$INI_FILE.sha256" ]; then
        SHA256_1=$(cat $CONFIG_DIR_APACHE/$INI_FILE.sha256)
        SHA256_2=$(cat $TMP_DIR/$INI_FILE.sha256)
        if [ "$SHA256_1" != "$SHA256_2" ]; then
            CONFIG_APACHE_UPDATE=yes
        fi
    else
        CONFIG_APACHE_UPDATE=yes
    fi
fi
CONFIG_FPM_UPDATE=no
if [ -n "$CONFIG_DIR_FPM" ] && [ -d "$CONFIG_DIR_FPM" ]; then
    if [ -f "$CONFIG_DIR_FPM/$INI_FILE" ] && [ -f "$CONFIG_DIR_FPM/$INI_FILE.sha256" ]; then
        SHA256_1=$(cat $CONFIG_DIR_FPM/$INI_FILE.sha256)
        SHA256_2=$(cat $TMP_DIR/$INI_FILE.sha256)
        if [ "$SHA256_1" != "$SHA256_2" ]; then
            CONFIG_FPM_UPDATE=yes
        fi
    else
        CONFIG_FPM_UPDATE=yes
    fi
fi
CONFIG_CLI_UPDATE=no
if [ -n "$CONFIG_DIR_CLI" ] && [ -d "$CONFIG_DIR_CLI" ]; then
    if [ -f "$CONFIG_DIR_CLI/$INI_FILE" ] && [ -f "$CONFIG_DIR_CLI/$INI_FILE.sha256" ]; then
        SHA256_1=$(cat $CONFIG_DIR_CLI/$INI_FILE.sha256)
        SHA256_2=$(cat $TMP_DIR/$INI_FILE.sha256)
        if [ "$SHA256_1" != "$SHA256_2" ]; then
            CONFIG_CLI_UPDATE=yes
        fi
    else
        CONFIG_CLI_UPDATE=yes
    fi
fi

# check if config file(s) have been changed
CONFIG_APACHE_CHANGED=no
if [ -n "$CONFIG_DIR_APACHE" ] && [ -d "$CONFIG_DIR_APACHE" ]; then
    if [ -f "$CONFIG_DIR_APACHE/$INI_FILE" ]; then
        if [ -f "$CONFIG_DIR_APACHE/$INI_FILE.sha256" ]; then
            check_sha256sum_installed
            SHA256_1=$(sha256sum $CONFIG_DIR_APACHE/$INI_FILE | awk {'print $1'})
            SHA256_2=$(cat $CONFIG_DIR_APACHE/$INI_FILE.sha256)
            if [ "$SHA256_1" != "$SHA256_2" ]; then
                CONFIG_APACHE_CHANGED=yes
            fi
        else
            CONFIG_APACHE_CHANGED=yes
        fi
    fi
fi
CONFIG_FPM_CHANGED=no
if [ -n "$CONFIG_DIR_FPM" ] && [ -d "$CONFIG_DIR_FPM" ]; then
    if [ -f "$CONFIG_DIR_FPM/$INI_FILE" ]; then
        if [ -f "$CONFIG_DIR_FPM/$INI_FILE.sha256" ]; then
            check_sha256sum_installed
            SHA256_1=$(sha256sum $CONFIG_DIR_FPM/$INI_FILE | awk {'print $1'})
            SHA256_2=$(cat $CONFIG_DIR_FPM/$INI_FILE.sha256)
            if [ "$SHA256_1" != "$SHA256_2" ]; then
                CONFIG_FPM_CHANGED=yes
            fi
        else
            CONFIG_FPM_CHANGED=yes
        fi
    fi
fi
CONFIG_CLI_CHANGED=no
if [ -n "$CONFIG_DIR_CLI" ] && [ -d "$CONFIG_DIR_CLI" ]; then
    if [ -f "$CONFIG_DIR_CLI/$INI_FILE" ]; then
        if [ -f "$CONFIG_DIR_CLI/$INI_FILE.sha256" ]; then
            check_sha256sum_installed
            SHA256_1=$(sha256sum $CONFIG_DIR_CLI/$INI_FILE | awk {'print $1'})
            SHA256_2=$(cat $CONFIG_DIR_CLI/$INI_FILE.sha256)
            if [ "$SHA256_1" != "$SHA256_2" ]; then
                CONFIG_CLI_CHANGED=yes
            fi
        else
            CONFIG_CLI_CHANGED=yes
        fi
    fi
fi

# copy INI file
EXIT_CODE=0
if [ "$CONFIG_APACHE_UPDATE" = "yes" ]; then
    if [ "$CONFIG_APACHE_CHANGED" = "yes" ]; then
        echo "$CONFIG_DIR_APACHE/$INI_FILE has been modified (or checksum file not found) so we won't replace it."
        echo "Instead the new config file will be stored as $CONFIG_DIR_APACHE/$INI_FILE.$REAL_VERSION."
        echo "Please transfer all custom changes to $CONFIG_DIR_APACHE/$INI_FILE.$REAL_VERSION and rename to $CONFIG_DIR_APACHE/$INI_FILE."
        cp $TMP_DIR/$INI_FILE $CONFIG_DIR_APACHE/$INI_FILE.$REAL_VERSION
        cp $TMP_DIR/$INI_FILE.sha256 $CONFIG_DIR_APACHE/
        EXIT_CODE=1
    else
        echo "Copying $TMP_DIR/$INI_FILE ($REAL_VERSION) to $CONFIG_DIR_APACHE/$INI_FILE ..."
        cp $TMP_DIR/$INI_FILE $CONFIG_DIR_APACHE/
        cp $TMP_DIR/$INI_FILE.sha256 $CONFIG_DIR_APACHE/
    fi
fi
if [ "$CONFIG_FPM_UPDATE" = "yes" ]; then
    if [ "$CONFIG_FPM_CHANGED" = "yes" ]; then
        echo "$CONFIG_DIR_FPM/$INI_FILE has been modified (or checksum file not found) so we won't replace it."
        echo "Instead the new config file will be stored as $CONFIG_DIR_FPM/$INI_FILE.$REAL_VERSION."
        echo "Please transfer all custom changes to $CONFIG_DIR_FPM/$INI_FILE.$REAL_VERSION and rename to $CONFIG_DIR_FPM/$INI_FILE."
        cp $TMP_DIR/$INI_FILE $CONFIG_DIR_FPM/$INI_FILE.$REAL_VERSION
        cp $TMP_DIR/$INI_FILE.sha256 $CONFIG_DIR_FPM/
        EXIT_CODE=1
    else
        echo "Copying $TMP_DIR/$INI_FILE ($REAL_VERSION) to $CONFIG_DIR_FPM/$INI_FILE ..."
        cp $TMP_DIR/$INI_FILE $CONFIG_DIR_FPM/
        cp $TMP_DIR/$INI_FILE.sha256 $CONFIG_DIR_FPM/
    fi
fi
if [ "$CONFIG_CLI_UPDATE" = "yes" ]; then
    if [ "$CONFIG_CLI_CHANGED" = "yes" ]; then
        echo "$CONFIG_DIR_CLI/$INI_FILE has been modified (or checksum file not found) so we won't replace it."
        echo "Instead the new config file will be stored as $CONFIG_DIR_CLI/$INI_FILE.$REAL_VERSION."
        echo "Please transfer all custom changes to $CONFIG_DIR_CLI/$INI_FILE.$REAL_VERSION and rename to $CONFIG_DIR_CLI/$INI_FILE."
        cp $TMP_DIR/$INI_FILE $CONFIG_DIR_CLI/$INI_FILE.$REAL_VERSION
        cp $TMP_DIR/$INI_FILE.sha256 $CONFIG_DIR_CLI/
        EXIT_CODE=1
    else
        echo "Copying $TMP_DIR/$INI_FILE ($REAL_VERSION) to $CONFIG_DIR_CLI/$INI_FILE ..."
        cp $TMP_DIR/$INI_FILE $CONFIG_DIR_CLI/
        cp $TMP_DIR/$INI_FILE.sha256 $CONFIG_DIR_CLI/
    fi
elif [ -n "$CONFIG_FILE_CLI" ] && [ -f "$CONFIG_FILE_CLI" ]; then
    echo "You must add/update these configurations inside $CONFIG_FILE_CLI:"
    echo
    echo "; ****************************************************************"
    echo "; ****************************************************************"
    cat $TMP_DIR/$INI_FILE
    echo "; ****************************************************************"
    echo "; ****************************************************************"
    echo
fi

# tidy up
tidy_up

echo
if [ "$EXIT_CODE" != "0" ]; then
    echo "Done installing the PHP agent. Could not update the config file(s). See logs above."
else
    echo "Done installing the PHP agent."
fi
exit $EXIT_CODE
