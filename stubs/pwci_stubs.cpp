// pw-ci link stubs for symbols whose sources were stripped from the public Prime World tree.
// Offline client only: none of these paths are exercised without a server.
#include <windows.h>

// ATL 7.1 (WDK) headers declare the thunk allocator but its lib does not provide it.
namespace ATL
{
  void* __stdcall __AllocStdCallThunk() { return VirtualAlloc( 0, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE ); }
  void  __stdcall __FreeStdCallThunk( void* p ) { if ( p ) VirtualFree( p, 0, MEM_RELEASE ); }
}

// Remote RPC factories generated into R*.auto.cpp files that are not published.
// Explicit specializations with empty bodies satisfy the linker; incomplete types are fine for pointer params.
//
// lobby::RIEntrance is NOT one of them: Game/PF/Server/LobbyPvx/RLobbyIEntrance.auto.cpp
// is published, it is just excluded by CMakeLists and re-added under the wrong path.
// An empty stub here links fine and registers nothing, so the client crashes the first
// time it queries the lobby Entrance - see cmake/pwci_extra.cmake.
namespace Monitoring { class RIMonitor; }
namespace rpc
{
  template <typename T> void RegisterRemoteFactory( T* instance );
  template <> void RegisterRemoteFactory<Monitoring::RIMonitor>( Monitoring::RIMonitor* ) {}
}
