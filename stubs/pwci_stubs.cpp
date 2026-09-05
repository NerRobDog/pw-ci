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
namespace lobby { class RIEntrance; }
namespace Monitoring { class RIMonitor; }
namespace rpc
{
  template <typename T> void RegisterRemoteFactory( T* instance );
  template <> void RegisterRemoteFactory<lobby::RIEntrance>( lobby::RIEntrance* ) {}
  template <> void RegisterRemoteFactory<Monitoring::RIMonitor>( Monitoring::RIMonitor* ) {}
}
