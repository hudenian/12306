#!/bin/bash
set -x
export CUSTOM_SEARCH_NAMES="application"
export CUSTOM_SEARCH_LOCATIONS=file:${BASE_DIR}/conf/
export MEMBER_LIST=""
PLUGINS_DIR="/home/nacos/plugins/peer-finder"
function print_servers() {
  if [[ ! -d "${PLUGINS_DIR}" ]]; then
    echo "" >"$CLUSTER_CONF"
    for server in ${NACOS_SERVERS}; do echo "$server" >>"$CLUSTER_CONF"; done
  else
    bash $PLUGINS_DIR/plugin.sh
    sleep 30
  fi
}
JAVA_OPT="${JAVA_OPT} -XX:+UseConcMarkSweepGC -XX:+UseCMSCompactAtFullCollection -XX:CMSInitiatingOccupancyFraction=70 -XX:+CMSParallelRemarkEnabled -XX:SoftRefLRUPolicyMSPerMB=0 -XX:+CMSClassUnloadingEnabled -XX:SurvivorRatio=8 -XX:-UseParNewGC"
# The bundled Java 8 crashes when Docker Desktop exposes cgroup v2. This must
# appear before -jar, so it is handled by the JVM rather than Spring Boot.
JAVA_OPT="${JAVA_OPT} -XX:-UseContainerSupport"
if [[ "${MODE}" == "standalone" ]]; then
  JAVA_OPT="${JAVA_OPT} -Xms${JVM_XMS} -Xmx${JVM_XMX} -Xmn${JVM_XMN} -Dnacos.standalone=true"
else
  if [[ "${EMBEDDED_STORAGE}" == "embedded" ]]; then JAVA_OPT="${JAVA_OPT} -DembeddedStorage=true"; fi
  JAVA_OPT="${JAVA_OPT} -server -Xms${JVM_XMS} -Xmx${JVM_XMX} -Xmn${JVM_XMN} -XX:MetaspaceSize=${JVM_MS} -XX:MaxMetaspaceSize=${JVM_MMS}"
  if [[ "${NACOS_DEBUG}" == "y" ]]; then JAVA_OPT="${JAVA_OPT} -Xdebug -Xrunjdwp:transport=dt_socket,address=9555,server=y,suspend=n"; fi
  JAVA_OPT="${JAVA_OPT} -XX:-OmitStackTraceInFastThrow -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${BASE_DIR}/logs/java_heapdump.hprof -XX:-UseLargePages"
  print_servers
fi
if [[ "${FUNCTION_MODE}" == "config" ]]; then JAVA_OPT="${JAVA_OPT} -Dnacos.functionMode=config"; elif [[ "${FUNCTION_MODE}" == "naming" ]]; then JAVA_OPT="${JAVA_OPT} -Dnacos.functionMode=naming"; fi
if [[ ! -z "${NACOS_SERVER_IP}" ]]; then JAVA_OPT="${JAVA_OPT} -Dnacos.server.ip=${NACOS_SERVER_IP}"; fi
if [[ ! -z "${USE_ONLY_SITE_INTERFACES}" ]]; then JAVA_OPT="${JAVA_OPT} -Dnacos.inetutils.use-only-site-local-interfaces=${USE_ONLY_SITE_INTERFACES}"; fi
if [[ ! -z "${PREFERRED_NETWORKS}" ]]; then JAVA_OPT="${JAVA_OPT} -Dnacos.inetutils.preferred-networks=${PREFERRED_NETWORKS}"; fi
if [[ ! -z "${IGNORED_INTERFACES}" ]]; then JAVA_OPT="${JAVA_OPT} -Dnacos.inetutils.ignored-interfaces=${IGNORED_INTERFACES}"; fi
if [[ ! -z "${NACOS_AUTH_ENABLE}" ]]; then JAVA_OPT="${JAVA_OPT} -Dnacos.core.auth.enabled=${NACOS_AUTH_ENABLE}"; fi
if [[ "${PREFER_HOST_MODE}" == "hostname" ]]; then JAVA_OPT="${JAVA_OPT} -Dnacos.preferHostnameOverIp=true"; fi
JAVA_OPT="${JAVA_OPT} -Dnacos.member.list=${MEMBER_LIST}"
JAVA_MAJOR_VERSION=$($JAVA -version 2>&1 | sed -E -n 's/.* version \"([0-9]*).*$/\1/p')
if [[ "$JAVA_MAJOR_VERSION" -ge "9" ]]; then
  JAVA_OPT="${JAVA_OPT} -Xlog:gc*:file=${BASE_DIR}/logs/nacos_gc.log:time,tags:filecount=10,filesize=102400"
else
  JAVA_OPT="${JAVA_OPT} -Xloggc:${BASE_DIR}/logs/nacos_gc.log -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100M"
fi
JAVA_OPT="${JAVA_OPT} -Dloader.path=${BASE_DIR}/plugins,${BASE_DIR}/plugins/health,${BASE_DIR}/plugins/cmdb,${BASE_DIR}/plugins/selector -Dnacos.home=${BASE_DIR} -jar ${BASE_DIR}/target/nacos-server.jar"
JAVA_OPT="${JAVA_OPT} --spring.config.additional-location=${CUSTOM_SEARCH_LOCATIONS} --spring.config.name=${CUSTOM_SEARCH_NAMES} --logging.config=${BASE_DIR}/conf/nacos-logback.xml --server.max-http-header-size=524288"
echo "Nacos is starting, you can docker logs your container"
exec $JAVA ${JAVA_OPT}
