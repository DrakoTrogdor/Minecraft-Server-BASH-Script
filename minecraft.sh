#!/bin/bash
#Written by Casey J. Sullivan
#Original Date: 2020-04-12 @ 00:01:00
#Last Update: 2020-06-29 17:44:00


#Boolean values which make saving configuration files and BASH script tests easier to intermingle
TRUE="TRUE"
FALSE="FALSE"

#Configuration file handling functions
script_config_init() {
    local _available_memory=$(echo $(($(getconf _AVPHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024) * 95 / 100)))
    [[ -z $MAXHEAP ]] && MAXHEAP="${_available_memory}M"
    [[ -z $MINHEAP ]] && MINHEAP="${_available_memory}M"
    [[ -z $CPU_COUNT ]] && CPU_COUNT=$(echo $(getconf _NPROCESSORS_ONLN))
    [[ -z $HISTORY ]] && HISTORY=1024
    [[ -z $OP_UUID ]] && OP_UUID="dd9b0cb4-4d8b-42ff-9e77-96acb39d3009"
    [[ -z $OP_NAME ]] && OP_NAME="DrakoTrogdor"
    [[ -z $USERNAME ]] && USERNAME='minecraft'
    [[ -z $GROUPNAME ]] && GROUPNAME='minecraft'
    [[ -z $WORLD ]] && WORLD='worlds'
    [[ -z $SERVICE ]] && SERVICE='server.jar'
    #[[ -z $ ]] && 
}
script_config_save() {
    local _config_file=${*}
    if [[ ! -f ${_config_file} || -w ${_config_file} ]]; then
        cat <<EOT > "${_config_file}"
MAXHEAP=${MAXHEAP}
MINHEAP=${MINHEAP}
CPU_COUNT=${CPU_COUNT}
HISTORY=${HISTORY}
OP_UUID=${OP_UUID}
OP_NAME=${OP_NAME}
USERNAME=${USERNAME}
GROUPNAME=${GROUPNAME}
WORLD=${WORLD}
SERVICE=${SERVICE}
EOT
        sudo chown ${USERNAME}:${GROUPNAME} ${_config_file}
        sudo chmod ug=rw,o=r ${_config_file}
    fi
}
script_config_load() {
    local _config_file=${*}
    if [[ -f $_config_file ]]; then
        while IFS='= ' read -r name value
        do
            if [[ ! $name =~ "^\ *#" && -n $name ]]; then
                value="${value%%\#*}"    # Del in line right comments
                value="${value%%*( )}"   # Del trailing spaces
                value="${value%\"*}"     # Del opening string quotes 
                value="${value#\"*}"     # Del closing string quotes 
                declare -g $name="$value"
            fi
        done < ${_config_file}
        script_config_init
        script_config_save  ${_config_file}
    else
        script_config_init
        script_config_save  ${_config_file}
    fi
}
#Settings
#dash does not support ${array[0]} therefore shebang (#!/bin/sh #!/bin/bash or #!/bin/dash) should be set to bash, otherwise $0 should be used.  BASH_SOURCE can be empty if no script is used, and $0 may not contain the path
SCRIPT=$(readlink -f "${BASH_SOURCE[0]}") #can also use $(realpath "${BASH_SOURCE[0]}")
SCRIPTFILE=$(basename "$SCRIPT")
SCRIPTPATH=$(dirname "$SCRIPT")
COMMAND=$1 && shift #Set "COMMAND" equal to the first argument
OPTION_NO_SERVICE=$FALSE
OPTION_NO_RECONNECT=$FALSE
OPTION_FULL_FIXPERMS=$FALSE
SCRIPTARGS="" #SCRIPTARGS=("$@")
while [[ $# -gt 0 ]] #Check the count of remaining arguments
do
  case "$1" in
    --no-service)
      OPTION_NO_SERVICE=$TRUE
      ;;
    --no-reconnect)
      OPTION_NO_RECONNECT=$TRUE
      ;;
    --full-fixperms)
      OPTION_FULL_FIXPERMS=$TRUE
      ;;
    --*)
      echo "Invalid Option: $1"
      ;;
    *)
      SCRIPTARGS="$SCRIPTARGS $1"
      ;;
    esac
    shift
done

#Initial variables required to load configuration file
PATH_ROOT='/opt/minecraft'
INSTANCE="${SCRIPTPATH##*/}"
PATH_INSTANCE="${PATH_ROOT}/${INSTANCE}"
PATH_CONFIG="${PATH_INSTANCE}/minecraft@${INSTANCE}.config"
script_config_load ${PATH_CONFIG}

#Remaining path variables
PATH_VERSION="${PATH_INSTANCE}/server_version.txt"
PATH_SERVICE="${PATH_INSTANCE}/${SERVICE}"
PATH_WORLD="${PATH_INSTANCE}/${WORLD}"
PATH_PLUGINS="${PATH_INSTANCE}/plugins"
PATH_BACKUP="${PATH_INSTANCE}/backups"

#Miscellaneous variables
ME=$(whoami)
SCREENNAME="Screen_${INSTANCE}"
OPTIONS='nogui'
UPGRADE_WORLD=$FALSE

#Aikar's suggested Parameters
PARAMS_AIKAR="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"
#Parameters common for all instances regardless of which GC implementation (normal, G1, Shenandoah, Z)
PARAMS_COMMON="-XX:+IgnoreUnrecognizedVMOptions -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+UseGCOverheadLimit -XX:MinHeapFreeRatio=40 -XX:MaxHeapFreeRatio=80 -XX:+ParallelRefProcEnabled -Dsun.rmi.dgc.server.gcInterval=2147483646 -Dusing.aikars.flags=mcflags.emc.gs"
#G1 Gabage Collection Parameters
#-XX:-UseParallelOldGC depreciated in v14.0
PARAMS_CUST_LOG="-Dlog4j.configurationFile=customlogging.xml"
PARAMS_GC_G1=" -XX:+DisableExplicitGC -XX:-UseParallelGC -XX:+UseG1GC -XX:MaxGCPauseMillis=75 -XX:TargetSurvivorRatio=70 -XX:G1NewSizePercent=25 -XX:G1MaxNewSizePercent=70 -XX:InitiatingHeapOccupancyPercent=10 -XX:G1MixedGCLiveThresholdPercent=40 -XX:G1HeapRegionSize=32M -XX:MinHeapFreeRatio=40 -XX:G1HeapWastePercent=5 -XX:GCTimeRatio=12 -XX:GCTimeLimit=98"
#Shenandoah Garbage Colleciton Parameters that might be worth looking into, some of the options were only added in JDK12+, currently set to default values from AdoptJDK13
PARAMS_GC_SHENP="-XX:+DisableExplicitGC -XX:-UseParallelGC -XX:-UseParallelOldGC -XX:+UseShenandoahGC -XX:ShenandoahAllocSpikeFactor=5 -XX:ShenandoahControlIntervalAdjustPeriod=1000 -XX:ShenandoahControlIntervalMax=10 -XX:ShenandoahControlIntervalMin=1 -XX:ShenandoahInitFreeThreshold=70 -XX:ShenandoahFreeThreshold=10 -XX:ShenandoahGarbageThreshold=60 -XX:ShenandoahGuaranteedGCInterval=300000 -XX:ShenandoahMinFreeThreshold=10 -XX:-ShenandoahRegionSampling -XX:ShenandoahRegionSamplingRate=40 -XX:ShenandoahParallelSafepointThreads=4 -XX:-ShenandoahOptimizeInstanceFinals -XX:+ShenandoahOptimizeStaticFinals"
#Z Garbage Collection Parameters. Experimental
PARAMS_GC_Z="-XX:+DisableExplicitGC -XX:-UseParallelGC -XX:-UseParallelOldGC -XX:-UseG1GC -XX:+UseZGC"
#Additional Experimental Parameters
# -XX:+UseFastUnorderedTimeStamps warning not to use on a AWS VM under OpenJDK14
PARAMS_EXP="-XX:+ExitOnOutOfMemoryError -XX:+AlwaysPreTouch -XX:+UseAdaptiveGCBoundary -XX:-DontCompileHugeMethods -XX:+TrustFinalNonStaticFields"
#Large Page Parameters
PARAMS_LP="-XX:+UseTransparentHugePages -XX:+UseLargePagesInMetaspace -XX:LargePageSizeInBytes=2M -XX:+UseLargePages"
#x86 Parameters.  Only use on specific architecture
PARAMS_XP="-XX:+UseCMoveUnconditionally -XX:+UseFPUForSpilling -XX:+UseNewLongLShift -XX:+UseVectorCmov -XX:+UseXMMForArrayCopy -XX:+UseXmmI2D -XX:+UseXmmI2F -XX:+UseXmmLoadAndClearUpper -XX:+UseXmmRegToRegMoveAll"
#Unused Parameters, you might want to use some of them depending on your configuration, copy the parameters under Normal Parameters, since IgnoreUnrecognizedVMOptions is set, unknown / invalid options will be ignored instead of stopping the JVM.
#-XX:ActiveProcessorCount=4 #This should restrict the use of CPU cores, although this is more of a suggestion than a constraint.
#-Xlog:gc*:file=GC.log #This will log GC to a file called GC.log, which can be used to debug GC, replace 'file=GB.log' with 'stdout' if you want logging to the console. Other options you can change/add pid,level,tags,...
#-Xlog:gc*:file=GC.log:time,uptimemillis,tid #Same as above, but with local time, uptime/runtime and thread IDs.
#-Xlog:gc*=debug:file=GC.log:time,uptimemillis,tid #Same as above, but with some extra debug. Warning: This is going to grow quickly!
#Working PARAMETER set for OpenJDK13
PARAMS_OpenJDK13="-XX:+UseG1GC -XX:+UnlockExperimentalVMOptions -XX:MaxGCPauseMillis=100 -XX:+DisableExplicitGC -XX:TargetSurvivorRatio=90 -XX:G1NewSizePercent=50 -XX:G1MaxNewSizePercent=80 -XX:G1MixedGCLiveThresholdPercent=35 -XX:G1HeapRegionSize=32M -XX:+AlwaysPreTouch -XX:+ParallelRefProcEnabled -Dsun.rmi.dgc.server.gcInterval=2147483646 -Dusing.aikars.flags=mcflags.emc.gs"

PARAMS_SET="-server -Xms${MINHEAP} -Xmx${MAXHEAP} -XX:ParallelGCThreads=${CPU_COUNT} ${PARAMS_AIKAR} ${PARAMS_CUST_LOG}" #$PARAMS_COMMON $PARAMS_GC_G1 $PARAMS_EXP $PARAMS_LP"
INVOCATION="/usr/bin/java $PARAMS_SET -jar $PATH_SERVICE $OPTIONS"
if [[ $(pidof systemd) ]]; then
    STATUS_SERVICE_ACTIVE=$([[ $(systemctl is-active minecraft@$INSTANCE.service 2> /dev/null) == "active" ]] && echo $TRUE || echo $FALSE)
else
    STATUS_SERVICE_ACTIVE=$FALSE
    OPTION_NO_SERVICE=$TRUE
fi
STATUS_SCREEN_RUNNING=$([[ -n $(sudo su - "${USERNAME}" -c "/usr/bin/screen -ls \"${SCREENNAME}\""|grep "${SCREENNAME}") ]] && echo $TRUE || echo $FALSE)

self_update() {
    echo "Updating ${SCRIPT} from github.com"
    sudo curl https://raw.githubusercontent.com/DrakoTrogdor/Minecraft-Server-BASH-Script/HEAD/minecraft.sh > ${SCRIPT}; exit 0
}

as_user() {
    SENDSTRING=${@}
    if [[ "$ME" == "$USERNAME" ]]; then
        bash -c "${SENDSTRING}"
    else
        sudo su - "${USERNAME}" -c "${SENDSTRING}"
    fi
}

mc_read_version() {
    read version < ${PATH_INSTANCE}/server_version.txt
}
mc_start() {
    if [[ $STATUS_SCREEN_RUNNING == $FALSE ]]; then
        if [[ $STATUS_SERVICE_ACTIVE == $TRUE ]]; then
            echo "Screen session is not found while service is reporting as active." | systemd-cat -p info 2> /dev/null || >&1
        fi
        echo "Starting Minecraft Server: $INSTANCE" | systemd-cat -p info 2> /dev/null || >&1

        local STARTUP_STRING="/usr/bin/screen -h ${HISTORY} -dmS \"${SCREENNAME}\" -T \"xterm-256color\" -U -O bash -c \"${INVOCATION} && exec bash -c 'echo Closing Normally...' || exec bash -c 'echo Abnormal Termination. This screen will close in 10s...;sleep 10s'\""
        [[ $UPGRADE_WORLD == $TRUE ]] && STARTUP_STRING="${STARTUP_STRING} --forceUpgrade"
        if [[ "$ME" == "$USERNAME" ]]; then
            bash -c "cd \"${SCRIPTPATH}\";${STARTUP_STRING}"
        else
            sudo su - "${USERNAME}" -c "cd \"${SCRIPTPATH}\";${STARTUP_STRING}"
        fi

        echo "Started Minecraft Server: $INSTANCE" | systemd-cat -p info 2> /dev/null || >&1
    else
        echo "Minecraft Server: $INSTANCE already started." | systemd-cat -p info 2> /dev/null || >&1
    fi
}

mc_stop() {
    echo "Stopping Minecraft Server: $INSTANCE" | systemd-cat -p info 2> /dev/null || >&1
    mc_send 'title @a times 20 160 20'
    mc_send 'title @a subtitle {"text":"Saving map...","color":"gray","italic":false,"bold":false}'
    mc_send 'title @a title {"text":"The server is shutting down now.","color":"red","italic":false,"bold":true}'
    mc_send 'title @a actionbar {"text":"Please log off in the next 10 seconds! (dig a hole quick)","color":"gold","italic":false,"bold":true}'
    /bin/sleep 10
    mc_send 'say The server is shutting down now.  Saving map...'
    mc_send 'save-all'
    mc_send 'stop'
    /bin/sleep 10
    echo "Stopped Minecraft Server: $INSTANCE" | systemd-cat -p info 2> /dev/null || >&1
}

mc_connect() {
    if [[ $STATUS_SCREEN_RUNNING == $FALSE ]]; then
        [[ $OPTION_NO_SERVICE == $TRUE ]] && mc_start || sudo systemctl start minecraft@$INSTANCE.service
    fi
    echo "Connecting to Minecraft Server: $INSTANCE..."
    sleep 1s
    as_user "/usr/bin/screen -r \"${SCREENNAME}\""
}

mc_reload() {
    echo "Reloading Minecraft Server: $INSTANCE" | systemd-cat -p info 2> /dev/null || >&1
    mc_send "reload confirm"
    echo "Reloaded Minecraft Server: $INSTANCE" | systemd-cat -p info 2> /dev/null || >&1
}

mc_download_server_jar() {
    #Arguments $1 == Build (e.g. Vanilla, Snapshot, Bukkit, Spigot, Paper); $2 == Revision (e.g. Spigot 1.16.1, Spigot 2738, Paper ver/1.16 )
    if [[ ! -w $PATH_INSTANCE ]]; then
        echo "No write permissions available for the instance folder.  Please user a different user or try using sudo."
        return 1
    fi
    cd $PATH_INSTANCE/
    local server_build=$1
    local revision=$2
    local download_successful=$FALSE
    case $server_build in
    Snapshot)
        MC_VERSION_MANIFEST=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)
        MC_SELECTED_ID=$(echo $MC_VERSION_MANIFEST | jq -r '.latest.snapshot')
        MC_SELECTED_MANIFEST=$(curl -s $(echo $MC_VERSION_MANIFEST | jq -r ".versions[] | select(.id==\"${MC_SELECTED_ID}\") | .url "))
        MC_SELECTED_URL=$(echo $MC_SELECTED_MANIFEST | jq -r '.downloads.server'.url)
        filename="vanilla_server_snapshot_${MC_SELECTED_ID}.jar"
        if [[ -f $PATH_INSTANCE/$filename ]]; then
            echo "'File \"${PATH_INSTANCE}/${filename}\" already exists."
            download_successful=$FALSE
        else
            curl $MC_SELECTED_URL -o $PATH_INSTANCE/$filename
            download_successful=$TRUE
        fi
        ;;
    Vanilla)
        MC_VERSION_MANIFEST=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)
        MC_SELECTED_ID=$(echo $MC_VERSION_MANIFEST | jq -r '.latest.release')
        MC_SELECTED_MANIFEST=$(curl -s $(echo $MC_VERSION_MANIFEST | jq -r ".versions[] | select(.id==\"${MC_SELECTED_ID}\") | .url "))
        MC_SELECTED_URL=$(echo $MC_SELECTED_MANIFEST | jq -r '.downloads.server'.url)
        filename="vanilla_server_release_${MC_SELECTED_ID}.jar"
        if [[ -f $PATH_INSTANCE/$filename ]]; then
            echo "'File \"${PATH_INSTANCE}/${filename}\" already exists."
            download_successful=$FALSE
        else
            curl $MC_SELECTED_URL -o $PATH_INSTANCE/$filename
            download_successful=$TRUE
        fi
        ;;
    Bukkit)
        # Download BuildTools and run as --compile 'CraftBukkit'
        curl "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" -o $PATH_INSTANCE/BuildTools.jar
        BUILD_TOOLS_OUTPUT=$(java -jar $PATH_INSTANCE/BuildTools.jar --compile 'CraftBukkit' | tee /dev/tty)
        #'  - Saved as ./craftbukkit-1.15.2.jar'
        filename=$(echo $BUILD_TOOLS_OUTPUT | grep -oP '(?<=\-\sSaved as\s\./)([A-Za-z0-9\.\-]+?)\.jar')
        download_successful=$TRUE
        ;;
    Spigot)
        # Download BuildTools and run as --compile 'Spigot'
        curl "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" -o $PATH_INSTANCE/BuildTools.jar
        BUILD_TOOLS_OUTPUT=$(java -jar $PATH_INSTANCE/BuildTools.jar | tee /dev/tty)
        #'  - Saved as ./spigot-1.15.2.jar'
        filename=$(echo $BUILD_TOOLS_OUTPUT | grep -oP '(?<=\-\sSaved as\s\./)([A-Za-z0-9\.\-]+?)\.jar')
        download_successful=$TRUE
        ;;
    Spigot-Rev)
        if [[ -z $response ]]; then
            revision='latest'
        fi
        # Download BuildTools and run as --compile 'Spigot'
        curl "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" -o $PATH_INSTANCE/BuildTools.jar
        BUILD_TOOLS_OUTPUT=$(java -jar $PATH_INSTANCE/BuildTools.jar --rev $revision | tee /dev/tty)
        #'  - Saved as ./spigot-1.15.2.jar'
        filename=$(echo $BUILD_TOOLS_OUTPUT | grep -oP '(?<=\-\sSaved as\s\./)([A-Za-z0-9\.\-]+?)\.jar')
        download_successful=$TRUE
        ;;
    Paper)
        # Download papermc
        #curl_output="$(curl https://papermc.io/api/v1/paper/${revision}/latest/download -OJ)"
        wget_output="$(wget -4 --content-disposition -nv https://papermc.io/api/v1/paper/${revision}/latest/download 2>&1 |cut -d\" -f2)"
        #if [[ -z "$curl_output" ]]; then
        if [ $? -ne 0 ]; then
            echo "File is already up to date."
            download_successful=$FALSE
        else
            # Defaults to paper-###.jar
            #filename="$(echo $curl_output | grep -oP "(?<=filename\ ').*(?=')")"
            filename=$wget_output
            download_successful=$TRUE
        fi
        ;;
    Paper-Rev)
        # Clone the Paper git repository and build
        if [[ -d $PATH_INSTANCE/Paper ]]; then
            cd $PATH_INSTANCE/Paper
            git checkout ${revision}
            git pull
        else
            if [[ -z $response ]]; then
                git clone https://github.com/PaperMC/Paper
            else
                git clone -b $revision https://github.com/PaperMC/Paper
            fi
        fi
        cd $PATH_INSTANCE/Paper
        $PATH_INSTANCE/Paper/paper jar
        #'  - Saved as ./paperclip.jar'
        filename='paperclip.jar'
        cp $PATH_INSTANCE/Paper/$filename $PATH_INSTANCE/$filename
        download_successful=$TRUE
        ;;
    *) ;;
    esac
    if [[ "${download_successful}" == $TRUE ]]; then
        # Remove server.jar if it already exists
        [[ -f ${PATH_INSTANCE}/${SERVICE} ]] && rm ${PATH_INSTANCE}/${SERVICE}
        # Create a sympolic link to server.jar from the latest build .jar
        ln -s "$PATH_INSTANCE/$filename" "${PATH_INSTANCE}/${SERVICE}"
    fi
    [[ $download_successful == $TRUE ]] && return 0 || return 1
}

mc_update() {
    if [[ ! -w $PATH_INSTANCE ]]; then
        echo "No write permissions available for the instance folder.  Please user a different user or try using sudo."
        return 1
    fi
    echo "Updating Minecraft Server: $INSTANCE"
    if [[ $STATUS_SCREEN_RUNNING == $TRUE ]]; then
        mc_send 'say A server update has been requested by the server administrator, but it will be back shortly...'
        [[ $STATUS_SERVICE_ACTIVE == $TRUE && $OPTION_NO_SERVICE == $FALSE ]] && sudo systemctl stop minecraft@$INSTANCE.service || mc_stop
        /usr/bin/sleep 30
    fi
    local version
    local revision
    read version revision < <(cat ${PATH_VERSION})
    mc_download_server_jar $version $revision
    if [[ $? -eq 0 ]]; then
        echo "Updated Minecraft Server: $INSTANCE"
        mc_fixperms
    else
        echo "Update of Minecraft Server: $INSTANCE was not successful"
    fi
    [[ $OPTION_NO_RECONNECT == $TRUE ]] || mc_connect #Reconnect only if OPTION_NO_RECONNECT equals false
}

mc_send() {
    echo "Sending->${*}"
    SENDSTRING="${*//\"/\\\\\"}"
    if [[ "$ME" = "$USERNAME" ]]; then
        bash -c "/usr/bin/screen -p 0 -S \"${SCREENNAME}\" -X eval 'stuff \"${SENDSTRING}\"\\015'"
    else
        sudo su "$USERNAME" -c "/usr/bin/screen -p 0 -S \"${SCREENNAME}\" -X eval 'stuff \"${SENDSTRING}\"\\015'"
    fi
}

mc_listen() {
    if [[ $STATUS_SCREEN_RUNNING == $TRUE ]]; then
        as_user "tail -f $PATH_INSTANCE/logs/latest.log"
    else
        echo "$INSTANCE is not running. Cannot listen to server."
    fi
}

mc_logs() {
    as_user "less -f $PATH_INSTANCE/logs/latest.log"
}

mc_saveon() {
    if [[ $STATUS_SCREEN_RUNNING == $TRUE ]]; then
        echo "Turning Saves On Minecraft Server: $INSTANCE"
        mc_send "save-on"
        echo "Turned Saves On Minecraft Server: $INSTANCE"
    else
        echo "$INSTANCE is not running. Cannot turn saves on."
    fi
}

mc_saveoff() {
    if [[ $STATUS_SCREEN_RUNNING == $TRUE ]]; then
        echo "Turning Saves Off Minecraft Server: $INSTANCE"
        mc_send "save-off"
        mc_send "save-all"
        echo "Turned Saves Off Minecraft Server: $INSTANCE"
    else
        echo "$INSTANCE is not running. Cannot turn saves off."
    fi
}

mc_backup() {
    echo "Backing Up Minecraft Server: $INSTANCE"

    declare -a folders=("${WORLD}/")
    declare -a files=("*.yml" "*.json" "*.properties")

    PLUGIN_SERVERRESTORER=$PATH_PLUGINS/ServerRestorer.jar
    [[ -f "$PLUGIN_SERVERRESTORER" ]] && BACKUP_METHOD=1 || BACKUP_METHOD=2
    
    
    #For TESTING
    BACKUP_METHOD=2
    
    
    
    case $BACKUP_METHOD in
    1) #ServerRestorer Plugin
        echo "Using ServerRestorer Plugin"
        ;;
    2) #Manual through TAR/GZ
        echo "Using TAR/GZ Backup"
        mc_saveoff
        NOW=$(date "+%Y-%m-%d_%Hh%M")
        BACKUP_FILE="${PATH_BACKUP}/${INSTANCE}_${NOW}.tar"
        echo "  Folders..."
        for FOLDER in "${folders[@]}"; do
            if [[ -d ${PATH_INSTANCE}/${FOLDER} ]]; then
                [[ -f ${BACKUP_FILE} ]] && as_user "tar -C ${PATH_INSTANCE} -rf ${BACKUP_FILE} ${FOLDER}" || as_user "tar -C ${PATH_INSTANCE} -cf ${BACKUP_FILE} ${FOLDER}"
            fi
        done
        echo "  Files..."
        for FILE in "${files[@]}"; do
            as_user "tar -C ${PATH_INSTANCE}/${FILE} -rf ${BACKUP_FILE}"
        done
        mc_saveon

        echo "Compressing backup..."
        as_user "gzip -f \"$BACKUP_FILE\""
        ;;
    3) #Amazon AWS bucket
        BUCKET="my.cool.bucket"
        for FOLDER in "${folders[@]}"; do
            [[ -d ${BASE_PATH}${FOLDER} ]] && tar -cz -C ${BASE_PATH} ${FOLDER} | aws s3 cp - s3://${BUCKET}/${FOLDER}-$(date '+%d').tgz
        done
        ;;
    esac
    echo "Backed Up Minecraft Server: $INSTANCE."
}

mc_fixperms() {
    echo "Repairing owners on directories, files, and symbolic links in \"$PATH_INSTANCE\"..."
    sudo find "$PATH_INSTANCE" -type d \( -path "*dynmap/web/tiles*" $( [[ $OPTION_FULL_FIXPERMS == "FALSE" ]] && printf "%s" "-o -path *${PATH_WORLD}*") \) -prune -o -type d,f,l -exec chown -h $USERNAME:$GROUPNAME {} \;
    echo "Repairing permissions on directories in \"$PATH_INSTANCE\"..."
    sudo find "$PATH_INSTANCE" -type d \( -path "*dynmap/web/tiles*" $( [[ $OPTION_FULL_FIXPERMS == "FALSE" ]] && printf "%s" "-o -path *${PATH_WORLD}*") \) -prune -o -type d -exec chmod 6775 {} \; #6775 = a+rwx,o-w,ug+s,+t,-t  where s and t are set uid and set gid (keeps root u/g)
    echo "Repairing permissions on files in \"$PATH_INSTANCE\"..."
    sudo find "$PATH_INSTANCE" -type d \( -path "*dynmap/web/tiles*" $( [[ $OPTION_FULL_FIXPERMS == "FALSE" ]] && printf "%s" "-o -path *${PATH_WORLD}*") \) -prune -o -type f -exec chmod ug+rw {} \;
    echo "Making scripts executable in \"$PATH_INSTANCE\"..."
    sudo find "$PATH_INSTANCE" -type d \( -path "*dynmap/web/tiles*" $( [[ $OPTION_FULL_FIXPERMS == "FALSE" ]] && printf "%s" "-o -path *${PATH_WORLD}*") \) -prune -o -name "*.sh" -type f -exec chmod +x {} \;
    #echo "Repairing permissions on symbolic links in \"$PATH_INSTANCE\"..."
    #sudo find "$PATH_INSTANCE" -type d \( -path "*dynmap/web/tiles*" $( [[ $OPTION_FULL_FIXPERMS == "FALSE" ]] && printf "%s" "-o -path *${PATH_WORLD}*") \) -prune -o -type l -exec chmod -h ug+rw {} \;
}

os_install_prerequisite() {
    if [[ "$EUID" -eq 0 ]]; then #Check if running as root
        PACKAGE=${@}
        if [[ -z $PACKAGE ]]; then
            echo -e "No package specified."
        else
            if [[ -n "$(command -v $PACKAGE)" ]]; then
                echo "Package or command \"${PACKAGE}\" is already available on this system."
            else
                echo "Package \"${PACKAGE}\" needs to be installed. Installing now..."
                declare -A PACKAGE_MANAGERS
                declare -A PACKAGE_UPDATE

                #Debian package mangement system (dpkg) front ends for Debian and Ubuntu.
                PACKAGE_MANAGERS[apt-get]="apt-get --yes install"
                PACKAGE_UPDATE[apt-get]="apt-get update"

                PACKAGE_MANAGERS[aptitude]="aptitude install"
                PACKAGE_UPDATE[aptitude]="aptitude update"

                #RPM pacakge management system (rpm) front ends for RedHat, Fedora, and CentOS
                PACKAGE_MANAGERS[yum]="yum install" #Yellow Dog Updater, Modified (YUM). RedHat.
                PACKAGE_UPDATE[yum]="yum update"

                PACKAGE_MANAGERS[dnf]="dnf -y install" #Dandified YUM (DNF). Fedora.
                PACKAGE_UPDATE[dnf]="dnf check-update" #Dandified YUM (DNF). Fedora.

                #Other package managers
                PACKAGE_MANAGERS[apk]="apk add --no-cache"
                PACKAGE_UPDATE[apk]="apk update"

                PACKAGE_MANAGERS[zypper]="zypper install" #SuSE
                PACKAGE_UPDATE[zypper]="zypper refresh"

                PACKAGE_MANAGERS[packman]="packman -S" #Arch Linux
                PACKAGE_UPDATE[packman]="packman -Syy"

                PACKAGE_MANAGERS[emerge]="emerge" #Portage package management system. Gentoo, Chrome OS, Sabayon, and Funtoo
                PACKAGE_UPDATE[emerge]="emaint -a sync"

                for manager in ${!PACKAGE_MANAGERS[@]}; do
                    if [[ -n "$(command -v $manager)" ]]; then
                        echo "Found package manager \"$manager\""
                        eval "${PACKAGE_UPDATE[$manager]}"
                        echo ${PACKAGE_MANAGERS[$manager]} $PACKAGE
                        eval "${PACKAGE_MANAGERS[$manager]} $PACKAGE"
                    fi
                done
            fi
        fi
    else
        echo echo -e "Please run as root."
    fi
}

os_detect_os() {
    case $OSTYPE in
    "linux-gnu")
        echo linux
        ;;
    "darwin"*)
        echo mac
        ;;
    "cygwin"|"msys"|"win32")
        echo windows
        ;;
    *)
        echo ""
        ;;
    esac
}
# Still need aarch64, ppc64le, s390x, x86-32
os_detect_architecture() {
    case $HOSTTYPE in
    "x86_64")
        echo "x64"
        ;;
    "arm")
        echo "arm"
        ;;
    *)
        echo ""
        ;;
    esac
}
os_install_java() {
    if [[ "$EUID" -eq 0 ]]; then #Check if running as root
        if [[ -n "$(command -v java)" ]]; then
            echo -e "Java already installed:\n\t$(java --version|grep -P '^OpenJDK')"
        else
            local this_OS=$(os_detect_os)
            local this_Arch=$(os_detect_architecture)
            local REPO="AdoptOpenJDK/openjdk16-binaries"
            local REPO_LATEST_RELEASE=$(curl --silent "https://api.github.com/repos/$REPO/releases" | jq -r ".[] | .assets[] | select((.content_type == \"application/x-compressed-tar\") or (.content_type == \"application/zip\")) | .browser_download_url" | grep -vP "(debugimage|testimage|alpine|windowsXL|linuxXL)" | grep -e "jre" | grep "hotspot" | grep "$this_OS" | grep "$this_Arch" | head -1)
            # Removed "| select(.prerelease == false)" from after jq -r ".[]"
            local FILENAME="${REPO_LATEST_RELEASE##*/}"
            if [[ -n "$REPO_LATEST_RELEASE" && -n "$FILENAME" ]]; then
                echo -e "Found AdopteOpenJDK:\n\tURL: $REPO_LATEST_RELEASE\n\tFile: $FILENAME"
                curl -L ${REPO_LATEST_RELEASE} -o $FILENAME
                if  [[ $(file -b $FILENAME) == "Zip archive data"* ]]; then
                    unzip $FILENAME
                    DIRNAME=$(unzip -l $FILENAME | head -4 | tail -1 | awk '{print $NF}' | cut -f1 -d"/")
                elif [[ $(file -b $FILENAME) == "gzip compressed data"* ]]; then
                    tar xf $FILENAME
                    DIRNAME=$(tar tzf $FILENAME | head -1 | cut -f1 -d"/")
                fi
                [[ -d /usr/lib/jvm ]] || mkdir -p /usr/lib/jvm/
                mv $DIRNAME /usr/lib/jvm/
                update-alternatives --install /usr/bin/java java /usr/lib/jvm/$DIRNAME/bin/java 1
            else
                echo -e "Could not find a suitable Java installation.\nPlease try installing manually."
            fi
        fi
    else
        echo echo -e "Please run as root."
    fi
}

mc_install() {
    if [[ "$EUID" -eq 0 ]]; then #Check if running as root
        echo Please select a version to install:
        local version
        local revision
        select version in 'Vanilla' 'Snapshot' 'Bukkit' 'Spigot' 'Spigot-Rev' 'Paper' 'Paper-Rev'; do
            echo "Version selected was $version"
            break
        done
        case "$version" in
            'Paper')
                revision='1.17.1'
                ;;
            'Spigot-Rev')
                echo "Please select a revision of Spigot to install"
                select revision in 'latest' '1.14' '1.14.1' '1.14.2' '1.14.3' '1.14.4' '1.15' '1.15.1' '1.15.2' '1.16' '1.16.1' '1.16.2' '1.16.3' '1.16.4' '1.16.5' '1.17' '1.17.1'; do
                    echo "Spigot Revision selected was $revision"
                    break
                done
                ;;
            'Paper-Rev')
                echo "Please select a brance of Paper to install"
                select revision in 'master' 'ver/1.14' 'ver/1.15.2' 'ver/1.16.5'; do
                    echo "Paper Branch selected was $revision"
                    break
                done
                ;;
            *)
                ;;
        esac


        echo "Enter a name for the new instance [ENTER]:"
        local response
        read response
        response=$(echo $response | sed -e 's/[^A-Za-z0-9._-]/_/g')
        if [[ -z $response ]]; then
            echo "Please enter a valid instance name."
        else
            if [[ -d "$PATH_ROOT/$response" ]]; then
                echo "The folder already exists.  Please use a different instance name."
            else
                #Install prerequisites:  sudo, curl, screen, java, git, ssh, whiptail
                # sudo
                os_install_prerequisite sudo
                # BASH Completion
                [[ -f /etc/profile.d/bash_completion.sh ]] && echo "Package or command \"bash_completion\" is already available on this system." || os_install_prerequisite bash-completion
                # curl - used to download manifests and files
                os_install_prerequisite curl
                # jq - Used to perform json searches
                os_install_prerequisite jq
                # file - Used to determine type of file
                os_install_prerequisite file
                # screen - Used to MUX the terminal
                os_install_prerequisite screen
                # lftp - Used to upload files for backup
                os_install_prerequisite lftp
                # git - Used for cloning repositories from github
                [[ $verion == 'Bukkit' || $version == 'Spigot' || $version == 'Spigot-Rev' ]] && os_install_prerequisite git

                # Java (must be setup after curl, due to script)
                os_install_java

                #Recreate the variables that rely in $INSTANCE name.
                INSTANCE=$response
                SCREENNAME="Screen_${INSTANCE}"
                PATH_INSTANCE="${PATH_ROOT}/${INSTANCE}"
                PATH_VERSION="${PATH_INSTANCE}/server_version.txt"
                PATH_SERVICE="${PATH_INSTANCE}/${SERVICE}"
                [[ $version == 'Snapshot' || $version == 'Vanilla' ]] && PATH_WORLD="${PATH_INSTANCE}" || PATH_WORLD="${PATH_INSTANCE}/${WORLD}"
                PATH_PLUGINS="${PATH_INSTANCE}/plugins"
                PATH_BACKUP="${PATH_INSTANCE}/backups"

                echo -e "\nCurrent Installation Information:"
                echo -e "\tInstance Name:\t\t${INSTANCE}"
                echo -e "\tRoot Path:\t\t${PATH_ROOT}"
                echo -e "\tInstance Path:\t\t${PATH_INSTANCE}"
                echo -e "\tVersion Path:\t\t${PATH_VERSION}"
                echo -e "\tService Path:\t\t${PATH_SERVICE}"
                echo -e "\tWorld Path:\t\t${PATH_WORLD}"
                echo -e "\tPlugins Path:\t\t${PATH_PLUGINS}"
                echo -e "\tBackup Path:\t\t${PATH_BACKUP}"

                #Check if the "minecraft" group exists. 0=Exists, 1=Does not Exists
                GROUP_EXISTS=$(
                    id -g $GROUPNAME >/dev/null 2>&1
                    echo $?
                )
                if [[ $GROUP_EXISTS -eq 0 ]]; then
                    echo "Group account for $GROUPNAME already exists."
                else
                    echo "Group account for $GROUPNAME does not exist. Creating now..."
                    groupadd -r $GROUPNAME
                fi

                #Check if the user specified by $USERNAME exists. 0=Exists, 1=Does not Exists
                USER_EXISTS=$(
                    id -u $USERNAME >/dev/null 2>&1
                    echo $?
                )
                if [[ $USER_EXISTS -eq 0 ]]; then
                    echo "User account for $USERNAME already exists."
                else
                    echo "User account for $USERNAME does not exist. Creating now..."
                    useradd -r -g $GROUPNAME -G sudo -d $PATH_ROOT $USERNAME #-r creates a system account (login), -g sets primary group, -G sets supplementary groups, -d sets home directory
                fi

                #Check if custom sudoers file exists and that it contains the correct data. If not create it.
                if [[ -f /etc/sudoers.d/$USERNAME ]]; then
                    grep -q "$USERNAME ALL=(ALL:ALL) NOPASSWD:ALL" /etc/sodoers.d/$USERNAME && echo "User $USERNAME is already in sudoers" || echo "$USERNAME ALL=(ALL:ALL) NOPASSWD:ALL" >>/etc/sudoers.d/$USERNAME
                else
                    echo "$USERNAME ALL=(ALL:ALL) NOPASSWD:ALL" >>/etc/sudoers.d/$USERNAME
                fi

                #Create home folder for $USERNAME and set it's permissions
                [[ -d $PATH_INSTANCE ]] || mkdir -p $PATH_INSTANCE
                chown $USERNAME:$GROUPNAME $PATH_ROOT
                chmod 6775 $PATH_ROOT

                #Change the default shell to BASH
                chsh -s /bin/bash $USERNAME

                #Copy default BASH scripts from /etc/skel/, add BASH completion if required and set permissions
                if [[ -f /etc/skel/.bashrc ]]; then
                    cp /etc/skel/.bashrc $PATH_ROOT/.bashrc
                    grep -wq '^source /etc/profile.d/bash_completion.sh' $PATH_ROOT/.bashrc || echo 'source /etc/profile.d/bash_completion.sh' >>$PATH_ROOT/.bashrc
                    chown $USERNAME:$GROUPNAME $PATH_ROOT/.bashrc
                    chmod ug+rw $PATH_ROOT/.bashrc
                fi

                if [[ -f /etc/skel/.bash_logout ]]; then
                    cp /etc/skel/.bash_logout $PATH_ROOT/.bash_logout
                    chown $USERNAME:$GROUPNAME $PATH_ROOT/.bash_logout
                    chmod ug+rw $PATH_ROOT/.bash_logout
                fi

                if [[ -f /etc/skel/.profile ]]; then
                    cp /etc/skel/.profile $PATH_ROOT/.profile
                    grep -q 'export SCREENDIR=\$HOME/.screen' $PATH_ROOT/.profile || echo \
'export SCREENDIR=$HOME/.screen
[ -d $SCREENDIR ] || mkdir -p -m 700 $SCREENDIR' \
                    >>$PATH_ROOT/.profile
                    chown $USERNAME:$GROUPNAME $PATH_ROOT/.profile
                    chmod ug+rw $PATH_ROOT/.profile
                fi

                if [[ -f /etc/skel/.bash_profile ]]; then
                    cp /etc/skel/.bash_profile $PATH_ROOT/.bash_profile
                    chown $USERNAME:$GROUPNAME $PATH_ROOT/.bash_profile
                    chmod ug+rw $PATH_ROOT/.bash_profile
                fi

                #Check for ls alias in .bash_aliases and add if it does not exist.
                grep -q "alias ls='LC_COLLATE=en_US.UTF-8 ls -CAh --time-style=long-iso --group-directories-first --color=yes'" $PATH_ROOT/.bash_aliases || echo "alias ls='LC_COLLATE=en_US.UTF-8 ls -CAh --time-style=long-iso --group-directories-first --color=yes'" >>$PATH_ROOT/.bash_aliases
                grep -q "alias ll='LC_COLLATE=en_US.UTF-8 ls -lAh --time-style=long-iso --group-directories-first --color=yes'" $PATH_ROOT/.bash_aliases || echo "alias ll='LC_COLLATE=en_US.UTF-8 ls -lAh --time-style=long-iso --group-directories-first --color=yes'" >>$PATH_ROOT/.bash_aliases
                chown $USERNAME:$GROUPNAME $PATH_ROOT/.bash_aliases
                chmod ug+rw $PATH_ROOT/.bash_aliases

                #Create the folder for the new instance and set it's owner and permissions
                mkdir -p $PATH_INSTANCE
                chown $USERNAME:$GROUPNAME $PATH_INSTANCE
                chmod 6775 $PATH_INSTANCE
                cd $PATH_INSTANCE

                #Download the latest server.jar based on the selected version
                mc_download_server_jar $version $revision

                if [[ $? -eq 0 ]]; then

                    echo "The \"${version}\" build of the Minecraft Server was successfully downloaded."

                    #Create required subfolders
                    [[ $version != 'Snapshot' && $version != 'Vanilla' ]] && mkdir $PATH_WORLD
                    mkdir $PATH_PLUGINS
                    mkdir $PATH_BACKUP

                    #Create a server_version.txt text file to help determine which version to update too later.
                    echo $version $revision > $PATH_VERSION

                    #Create a eula.txt file with the eula set to true
                    echo "eula=true" >$PATH_INSTANCE/eula.txt

                    #Create a starter server.properties file for the instance with required settings. Default settings will be added automatically.
                    echo \
"allow-flight=true
difficulty=normal
enable-command-block=true
motd=Welcome to the $INSTANCE Minecraft Server
spawn-protection=0" \
                        >$PATH_INSTANCE/server.properties

                    #Create a starter ops.json file for the instance with OP_UUID and OP_USERNAME so that they are automatically added
                    echo "[\n  {\n    \"uuid\": \"$OP_UUID\",\n    \"name\": \"$OP_NAME\",\n    \"level\": 4,\n    \"bypassesPlayerLimit\": true\n  }\n]" >$PATH_INSTANCE/ops.json

                    #Create a starter bukkit.yml file for the instance with required settings. Default settings will be added automatically.
                    [[ $verion == 'Bukkit' || $version == 'Spigot' || $version == 'Spigot-Rev' || $version == 'Paper' ]] && echo \
"settings:
  world-container: worlds" \
                        >$PATH_INSTANCE/bukkit.yml

                    #Create a starter spigot.yml file for the instance with required settings. Default settings will be added automatically.
                    [[ $version == 'Spigot' || $version == 'Spigot-Rev' || $version == 'Paper' ]] && echo \
"settings:
  restart-script: $PATH_INSTANCE/minecraft.sh start" \
                        >$PATH_INSTANCE/spigot.yml

                    #Create a starter paper.yml file for the instance with required settings. Default settings will be added automatically.
                    [[ $version == 'Paper' ]] && echo \
"allow-perm-block-break-exploits: true
settings:
  unsupported-settings:
    allow-piston-duplication: true
world-settings:
  default:
    fix-zero-tick-instant-grow-farms: false
    optimize-explosions: true
    use-faster-eigencraft-redstone: false" \
                        >$PATH_INSTANCE/paper.yml

                    #Create a systemd service unit file
                    echo \
"[Unit]
Description=Minecraft Server Instance: %i
After=local-fs.target network.target

[Service]
WorkingDirectory=/opt/minecraft/%i
User=minecraft
Group=minecraft
Type=forking

ExecStart=/bin/bash -c '/opt/minecraft/%i/minecraft.sh service_start'

ExecStop=/bin/bash -c '/opt/minecraft/%i/minecraft.sh service_stop'

[Install]
WantedBy=multi-user.target" \
                        >$PATH_INSTANCE/minecraft\@$INSTANCE.service

                    #Enable the server
                    systemctl enable $PATH_INSTANCE/minecraft@$INSTANCE.service

                    #Copy this script to the instance folder
                    echo "Copying \"$SCRIPT\" to \"${PATH_INSTANCE}/minecraft.sh\""
                    cp "$SCRIPT" "${PATH_INSTANCE}/minecraft.sh"
                    COMPLETION_WORDS="start stop status restart reload update backup connect send listen logs install fixperms instances enable disable"
                    complete -W "${COMPLETION_WORDS}" $PATH_INSTANCE/minecraft.sh #Add autocompleteion for /minecraft.sh command
                    complete -W "${COMPLETION_WORDS}" ./minecraft.sh              #Add autocompleteion for /minecraft.sh command

                    #Create a symbolic link to /usr/bin/mc from this script if /usr/bin/mc doesn't already exist
                    if [[ -L "/usr/bin/mc" || -e "/usr/bin/mc" ]]; then
                        echo "/usr/bin/mc already exists.  Creating mc_${INSTANCE}"
                        ln -s $PATH_INSTANCE/minecraft.sh /usr/bin/mc_${INSTANCE}
                        complete -W "${COMPLETION_WORDS}" mc_${INSTANCE}          #Add autocompleteion for mc command
                        complete -W "${COMPLETION_WORDS}" /usr/bin/mc_${INSTANCE} #Add autocompleteion for mc command
                    else
                        ln -s $PATH_INSTANCE/minecraft.sh /usr/bin/mc
                        complete -W "${COMPLETION_WORDS}" mc          #Add autocompleteion for mc command
                        complete -W "${COMPLETION_WORDS}" /usr/bin/mc #Add autocompleteion for mc command
                    fi

                    #Set/fix all permissions on files for this instance.
                    mc_fixperms
                else
                    echo "There was an error downloading the \"${version}\" build of the Minecraft Server."
                fi
            fi
        fi
    else
        echo -e "Please run as root using:\n\tsudo $0 install"
    fi
}

case "$COMMAND" in
service_start)
    mc_start
    ;;
service_stop)
    mc_stop
    ;;
status)
    systemctl status minecraft@$INSTANCE.service 2> /dev/null || retval=$(as_user screen -ls "${SCREENNAME}"|grep "${SCREENNAME}"); [[ -n $retval ]] && echo $retval || echo "Status unavailable."
    ;;
start)
    [[ $OPTION_NO_SERVICE == $TRUE ]] && mc_start || sudo systemctl start minecraft@$INSTANCE.service
    ;;
stop)
    [[ $OPTION_NO_SERVICE == $TRUE ]] && mc_stop || sudo systemctl stop minecraft@$INSTANCE.service
    ;;
restart)
    mc_stop
    /usr/bin/sleep 10
    mc_start
    ;;
reload)
    mc_reload
    ;;
update)
    mc_update
    ;;
backup)
    mc_backup
    ;;
connect)
    mc_connect
    ;;
send)
    mc_send "${SCRIPTARGS}"
    ;;
listen)
    mc_listen
    ;;
logs)
    mc_logs
    ;;
install)
    mc_install
    ;;
fixperms)
    mc_fixperms
    ;;
fetch)
    self_update
    ;;
test)
    TEST_VAR="${SCRIPTARGS}"
    echo "Input is : $TEST_VAR"
    if [[ $TEST_VAR == "java" ]]; then
        os_install_java
    else
        os_install_prerequisite "${SCRIPTARGS}"
    fi
    ;;
instances)
    sudo systemctl list-units "minecraft@*.service" --all
    ;;
enable)
    sudo systemctl enable $PATH_INSTANCE/minecraft@$INSTANCE.service
    ;;
disable)
    sudo systemctl disable minecraft@$INSTANCE.service
    ;;
*)
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo "COMMAND:"
    echo -e "\tstart\t\tStart the Minecraft server."
    echo -e "\tstop\t\tStop the Minecraft server."
    echo -e "\trestart\t\tRestart the Minecraft server."
    echo -e "\tstatus\t\tRetrieve the status of the Minecraft server service."
    echo -e "\tinstances\tList all Mincraft server service instances."
    echo -e "\tenable\t\tEnable this Mincraft server service instance."
    echo -e "\tdisable\t\tDisable this Mincraft server service instance."
    echo -e "\tupdate\t\tUpdate to the latest version of which-ever flavor of Minecraft was installed."
    echo -e "\tconnect\t\tConnect to the Minecraft server console."
    echo -e "\treload\t\tSend the \"reload\" command to the Minecraft server."
    echo -e "\tsend\t\tSend command to the Minecraft server. This accepts any minecraft command for the OPTION argument."
    echo -e "\tlisten\t\tShow console history. This updates as the console is updated."
    echo -e "\tlogs\t\tView the latest server log."
    echo -e "\tfixperms\tFix file permissions for the Minecraft server folder and sub folders."
    echo -e "\tinstall\t\tSetup and configure a new instance of PaperMC using the latest version in the current folder."
    echo -e "\tfetch\t\tFetches the latest version of this script."
    echo -e "\tbackup\t\tBackup the current server."
    echo -e "\nOPTIONS:"
    echo -e "\t--no-service\tStart without invoking the systemd service."
    echo -e "\t--no-reconnect\tBypass reconnecting after an update."
    echo -e "\t--full-fixperms\tFix permissions on all files/folders including in the world folder."
    echo -e "\nCurrent Instance Information:"
    echo -e "\tInstance:\t\"$INSTANCE\""
    echo -e "\tPath:\t\t\"$PATH_INSTANCE\""
    echo -e "\tInvocation:\t\"/usr/bin/java \$PARAMETERS -jar $PATH_SERVICE $OPTIONS\""
    echo -e "\tParameters:"
    # Determine how many columns can be displayed on the screen at one time (upto four, because I like that).
    length_tabs=$(echo -e "\t\t\t"|wc -L) #This should be 8*3=24, but it is possible to adjust each tab individually using the tabs command. Not sure how to fix.
    length_largest_param=$(( $(echo "$PARAMS_SET"|sed 's/\s/\n/g'|wc -L) + 2 )) #Two spaces are added between rows
    width_screen=$(tput cols)
    max_columns=$(( (($width_screen-$length_tabs)/$length_largest_param) ))
    # Replace SPACE with TAB
    #     sed 's/\s/\t/g'
    # Replace every third TAB with an ENTER.  Max number should be divisible by repititions or it will not align properly
    #     sed '-es/\t/\n/'{999..1..3}
    # Format as proper columns in a table
    #     column -t
    # Indent each new line by three TABs
    #     sed -e 's/^/\t\t\t/'
    if (( $max_columns >= 4 )); then
        echo $PARAMS_SET|sed 's/\s/\t/g'|sed '-es/\t/\n/'{1000..1..4}|column -t|sed -e 's/^/\t\t\t/'
    elif (( $max_columns == 3 )); then
        echo $PARAMS_SET|sed 's/\s/\t/g'|sed '-es/\t/\n/'{999..1..3}|column -t|sed -e 's/^/\t\t\t/'
    elif (( $max_columns == 2 )); then
        echo $PARAMS_SET|sed 's/\s/\t/g'|sed '-es/\t/\n/'{1000..1..2}|column -t|sed -e 's/^/\t\t\t/'
    else
        echo $PARAMS_SET|sed 's/\s/\n/g'|sed -e 's/^/\t\t\t/'
    fi
    echo -e "\tService Active:\t\"$STATUS_SERVICE_ACTIVE\""
    echo -e "\tScreen Running:\t\"$STATUS_SCREEN_RUNNING\""
    ;;
esac
exit 0
