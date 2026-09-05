# pw-ci: re-add sources Nival's blanket exclusions dropped but the client links against,
# plus vendor libs the original CMakeLists never listed. Included right before add_executable.

# --- sources present in the published tree ---
set( ALL_SRCS ${ALL_SRCS}
  ${SRC_DIR}/Game/PF/Server/LobbyPvx/CommonTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatisticsClientTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatisticsCommonTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatisticsDebugTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/GameStatClient.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatClientDiskDispatcher.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatClientHttpDispatcher.cpp
  ${SRC_DIR}/Server/ServerAppBase/NivalService.cpp
  ${SRC_DIR}/Server/Monitoring/PerfCounterProvider/PerfCounter.cpp
  ${SRC_DIR}/Game/PF/HybridServer/RPeered.auto.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/SpecialStatisticTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Roll/RollTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Censorship/CensorClient.cpp
  ${SRC_DIR}/Game/PF/Server/Censorship/CensorJob.cpp
  ${SRC_DIR}/Game/PF/Server/Censorship/CensorSettings.cpp
  ${SRC_DIR}/Server/Monitoring/PerfCounterProvider/LPerfCounterProviderIface.auto.cpp
  ${VENDOR}/MD4/md4c.c
  ${VENDOR}/MD4/md5c.c
  ${SRC_DIR}/pwci_stubs.cpp
)

# Vendor/libcurl/lib/Release/libcurl.lib is a static build (exports _curl_*, no __imp__),
# same as Nival's vcproj which defined CURL_STATICLIB. Static curl pulls winsock + ldap.
add_definitions( -DCURL_STATICLIB )
include_directories( ${SRC_DIR}/Server/Monitoring ${SRC_DIR}/Game/PF/Server ${VENDOR}/tinyxml/src )

# --- vendor / tool libs ---
simple_add_library( wbemuuid )
simple_add_library( ws2_32 )
simple_add_library( wldap32 )
simple_add_library( ${VENDOR}/tinyxml/Release/tinyxml )
simple_add_library( ${VENDOR}/JsonCpp/lib/Release/JsonCpp )
simple_add_library( ${VENDOR}/libcurl/lib/Release/libcurl )
simple_add_library( ${SRC_DIR}/../Tools/Censor/lib/Release/CensorDll )

# --- static-init order ---
# MSVC runs global constructors in link (object) order. The DLL build initialised
# System.dll first and PW_Client.dll last; the monolithic GLOB order is alphabetical
# (Client/... before System/...), so constructors in Client/Core ran before the
# System globals they touch existed -> zeroed CRITICAL_SECTION deadlock at startup
# ("RtlpWaitForCriticalSection ... blocked by 0000"). Re-emit ALL_SRCS in DLL
# dependency order from PF.sln; unmatched dirs (Game/PF/Server, Server/*, Vendor, stubs) go last.
set( PWCI_INIT_ORDER
  MemoryLib System libdb Sound NivalInput Render Terrain Scripts Scene UI
  Server/RPC Network Core Client PF_Core PF_GameLogic
  Server/NetworkAIO Game/PF/Client PF_Minigames PW_Client PW_Game )
set( _pwci_rest ${ALL_SRCS} )
set( _pwci_sorted )
foreach( _d ${PWCI_INIT_ORDER} )
  set( _m ${_pwci_rest} )
  list( FILTER _m INCLUDE REGEX "/Src/${_d}/" )
  list( APPEND _pwci_sorted ${_m} )
  list( FILTER _pwci_rest EXCLUDE REGEX "/Src/${_d}/" )
endforeach()
set( ALL_SRCS ${_pwci_sorted} ${_pwci_rest} )
list( LENGTH _pwci_sorted _n1 )
list( LENGTH _pwci_rest _n2 )
message( STATUS "pwci: init-order sorted ${_n1} sources, ${_n2} unmatched appended last" )
