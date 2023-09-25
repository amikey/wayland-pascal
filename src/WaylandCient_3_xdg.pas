program WaylandClient_3_xdg;

{$mode objfpc}{$H+}

uses
  ctypes,
  BaseUnix,
  wayland_client_core,
  wayland_protocol,
  xdg_shell_protocol,
  SysUtils;

type
  pwl_registry = Pointer;

type
  pwl_registry_listener = ^wl_registry_listener;

  wl_registry_listener = record
    global: procedure(Data: Pointer; registry: pwl_registry; Name: longword; interface_: PChar; version: longword); cdecl;
    global_remove: procedure(Data: Pointer; registry: pwl_registry; Name: longword); cdecl;
  end;

const
  XDG_TOPLEVEL_SET_TITLE_ = 2;
  XDG_WM_BASE_GET_XDG_SURFACE_ = 2;
  XDG_SURFACE_ACK_CONFIGURE_ = 4;
  XDG_SURFACE_GET_TOPLEVEL_ = 1;
  XDG_WM_BASE_PONG_ = 3;
var
  display: Pwl_display;
  registry: Pwl_registry;
  shm: Pwl_shm;
  compositor: Pwl_compositor;
  xdg_wm_base: Pxdg_wm_base;
  surface: Pwl_surface;
  xdg_surface: Pxdg_surface;
  xdg_toplevel: Pxdg_surface;
  tmpdata: string = '';

  function xdg_wm_base_get_xdg_surface(xdg_wm_base: Pxdg_wm_base; surface: Pwl_surface): Pxdg_surface;
  var
    id: Pwl_proxy;
    inte: integer;
  begin
    id := nil;

    inte := wl_proxy_get_version(Pwl_proxy(xdg_wm_base));
    writeln('xdg version ' + IntToStr(inte));

    id := wl_proxy_marshal_flags_get_xdg_surface(
      Pwl_proxy(xdg_wm_base),
      XDG_WM_BASE_GET_XDG_SURFACE_, @xdg_surface_interface,
      wl_proxy_get_version(Pwl_proxy(xdg_wm_base)),
      0,
      nil,
      surface
      );

    Result := Pxdg_surface(id);

    if Result = nil then
      writeln('Pxdg_surface NOT OK ')
    else
      writeln('Pxdg_surface OK ');
  end;

  function allocate_shm_file(size: csize_t): cint;
  var
    fd, ret: cint;
    nullByte: byte;
  begin
    tmpdata := 'test.dat';
    Fd      := FileCreate(tmpdata);
    //writeln('allocate_shm_file fd = ' + inttostr(fd));
    if fd < 0 then
      Exit(-1);
    // Seek to the desired size and truncate the file
    FileSeek(fd, int64(size) - 1, 0);
    nullByte := 0;
    FileWrite(fd, nullByte, 1);
    fpClose(fd);
    fd       := fpOpen('test.dat', O_RDWR);
    Result   := fd;
  end;

  function draw_frame(state: Pwl_display): Pwl_buffer;
  var
    size, stride, fd, x, y: integer;
    s: string = '*';
    Data: ^longword;
    pool: Pwl_shm_pool;
    buffer: Pwl_buffer;
    Width, Height: integer;
  begin

    //writeln('draw_frame init');

    Width  := 400;
    Height := 400;

    stride := Width * 4; // Adjust based on pixel format
    size   := stride * Height;

    //writeln('size = ' + inttostr(size));

    fd := allocate_shm_file(size);

    if fd = -1 then
    begin
      writeln('allocate_shm_file = BAD');
      Exit(nil); // Return nil in case of failure
    end;

    // writeln('before FpMmap') ; 

    Data := (FpMmap(nil, size + 1, PROT_READ or PROT_WRITE, MAP_SHARED, fd, 0));

    if Data = MAP_FAILED then
    begin
      writeln('data = MAP_FAILED');
      fpclose(fd);
      Exit(nil); // Return nil in case of failure
    end;
    //else  writeln('data = OK');

    // writeln('before pool') ; 
    pool := nil;

    pool := wrap_wl_shm_create_pool(shm, fd, size);
    // if pool = nil then writeln('wrap_wl_shm_create_pool = NOT OK') else writeln('wrap_wl_shm_create_pool = OK');

    buffer := wrap_wl_shm_pool_create_buffer(pool, 0, Width, Height, stride, WL_SHM_FORMAT_XRGB8888);
    //if buffer = nil then writeln('wrap_wl_shm_pool_create_buffer = NOT OK') else writeln('wrap_wl_shm_pool_create_buffer = OK');

    wrap_wl_shm_pool_destroy(pool);

    fpclose(fd);

    { Draw checkerboard background }
    for y := 0 to Height - 1 do
      for x := 0 to Width - 1 do
        if (x div 50 + y div 50) mod 2 = 0 then
          Data[y * Width + x] := $FF834555 // Set pixel color
        else
          Data[y * Width + x] := $FFEEEEEE;

    FpMunmap(Data, size);

    wrap_wl_surface_attach(surface, buffer, 0, 0);
    wrap_wl_surface_commit(surface);

    Result := buffer; // Return the created buffer
  end;

  procedure xdg_surface_ack_configure(xdg_surface: Pxdg_surface; serial: DWord);
  begin
    // if xdg_surface <> nil then writeln('xdg_surface OK') else
    //  writeln('xdg_surface NOT OK') ;

    // if Pwl_proxy(xdg_surface) <> nil then writeln('Pwl_proxy(xdg_surface) OK') else
    //  writeln('Pwl_proxy(xdg_surface) NOT OK') ;

    wl_proxy_marshal_flags_ack_configure(

      Pwl_proxy(xdg_surface),
      XDG_SURFACE_ACK_CONFIGURE_,
      nil,
      wl_proxy_get_version(Pwl_proxy(xdg_surface)),
      0,
      serial);

  end;

  procedure xdg_surface_configure(Data: Pointer; xdg_surface: Pxdg_surface; serial: cuint); cdecl;
  var
    state: Pwl_display = nil;
    buffer: Pwl_buffer = nil;
  begin
    state := Pwl_display(Data);

    //  if state <> nil then writeln('state OK') else
    //  writeln('state NOT OK') ;

    // if xdg_surface <> nil then writeln('xdg_surface OK') else
    //writeln('xdg_surface NOT OK') ;

    //writeln('serial = ' + inttostr(serial)) ;

    xdg_surface_ack_configure(xdg_surface, serial);

    buffer := draw_frame(state);

    if buffer <> nil then
    begin
      wrap_wl_surface_attach(surface, buffer, 0, 0);
      wrap_wl_surface_commit(surface);
      //writeln('buffer xdg_surface_configure OK') ;
    end
    else
      writeln('buffer xdg_surface_configure NOT OK');
  end;

  procedure xdg_wm_base_ping(Data: Pointer; xdg_wm_base: Pxdg_wm_base; serial: cuint); cdecl;
  begin
    wl_proxy_marshal_flags_ping(
      Pwl_proxy(xdg_wm_base),
      XDG_WM_BASE_PONG_,
      nil,
      wl_proxy_get_version(Pwl_proxy(xdg_wm_base)),
      0,
      serial
      );
  end;

type
  TXdgWmBaseListener = record
    ping: procedure(Data: Pointer; xdg_wm_base: Pxdg_wm_base; serial: cuint); cdecl;
  end;

  procedure xdg_wm_base_add_listener(xdg_wm_base: Pxdg_wm_base; listener: TXdgWmBaseListener; Data: Pointer);
  begin
    if @listener.ping <> nil then
      wl_proxy_add_listener(Pwl_proxy(xdg_wm_base), @listener.ping, Data);
  end;

  function xdg_surface_add_listener(xdg_surface: Pxdg_surface; listener: Pxdg_surface_listener; Data: Pointer): longint;
  begin
    Result := wl_proxy_add_listener(Pwl_proxy(xdg_surface), Pointer(listener), Data);
  end;

  procedure registry_global(Data: Pointer; wl_registry: Pwl_registry; Name: cuint; iface: PChar; version: cuint); cdecl;
  var
    state: Pwl_display;
    XdgWmBaseListener: TXdgWmBaseListener;
  begin
    state        := Pwl_display(Data);
    if AnsiCompareStr(iface, wl_shm_interface.Name) = 0 then
      shm        := wrap_wl_registry_bind(wl_registry, Name, @wl_shm_interface, 1)
    else if AnsiCompareStr(iface, wl_compositor_interface.Name) = 0 then
      compositor := wrap_wl_registry_bind(wl_registry, Name, @wl_compositor_interface, 4)

    else if AnsiCompareStr(iface, xdg_wm_base_interface.Name) = 0 then
    begin
      xdg_wm_base := wrap_wl_registry_bind(wl_registry, Name, @xdg_wm_base_interface, 1);

      // Initialize your listener
      XdgWmBaseListener.ping := @xdg_wm_base_ping;

      xdg_wm_base_add_listener(xdg_wm_base, XdgWmBaseListener, state);
    end;
  end;

  function xdg_surface_get_toplevel(xdg_surface: Pxdg_surface): Pxdg_toplevel;
  begin
    Result := Pxdg_toplevel(
      wl_proxy_marshal_flags_get_toplevel(
      Pwl_proxy(xdg_surface),
      XDG_SURFACE_GET_TOPLEVEL_, @xdg_toplevel_interface,
      wl_proxy_get_version(Pwl_proxy(xdg_surface)),
      0,
      nil
      )
      );
  end;

  procedure xdg_toplevel_set_title(xdg_toplevel: Pxdg_toplevel; title: PChar);
  begin

    wl_proxy_marshal_flags_set_title(
      Pwl_proxy(xdg_toplevel),
      XDG_TOPLEVEL_SET_TITLE_,
      nil,
      wl_proxy_get_version(Pwl_proxy(xdg_toplevel)),
      0,
      title
      );
  end;

  procedure registry_global_remove(Data: Pointer; wl_registry: Pwl_registry; Name: cuint); cdecl;
  begin
    { This space deliberately left blank }
  end;

var
  listener: Twl_registry_listener;
  xdg_surface_listener: Txdg_surface_listener;
  xdg_wm_base_listener: Txdg_surface_listener;

begin
  { Initialize Wayland objects }
  shm         := nil;
  compositor  := nil;
  xdg_wm_base := nil;
  surface     := nil;

  { Connect to the Wayland display }
  display := wl_display_connect(nil);
  if display <> nil then
    writeln('Display connected')
  else
    writeln('Display not connected');

  registry := wrap_wl_display_get_registry(display);
  if registry <> nil then
    writeln('registry connected')
  else
    writeln('registry not connected');

  listener.global := @registry_global;
  writeln('listener.global');

  listener.global_remove := @registry_global_remove;
  writeln('listener.global_remove');

  wrap_wl_registry_add_listener(registry, @listener, display);
  writeln('wrap_wl_registry_add_listener');

  wl_display_roundtrip(display);
  writeln('wl_display_roundtrip');

  surface := wrap_wl_compositor_create_surface(compositor);
  if surface <> nil then
    writeln('surface connected')
  else
    writeln('surface not connected');

  xdg_surface := xdg_wm_base_get_xdg_surface(xdg_wm_base, surface);
  if xdg_surface <> nil then
    writeln('xdg_surface connected')
  else
    writeln('xdg_surface not connected');

  xdg_surface_listener.configure := @xdg_surface_configure;
  writeln('xdg_surface_listener.configure');

  xdg_surface_add_listener(xdg_surface, @xdg_surface_listener, display);
  writeln('xdg_surface_add_listener');

  xdg_toplevel := xdg_surface_get_toplevel(xdg_surface);
  if xdg_toplevel <> nil then
    writeln('xdg_toplevel connected')
  else
    writeln('xdg_toplevel not connected');

  xdg_toplevel_set_title(xdg_toplevel, 'Example client');
  writeln('xdg_toplevel_set_title');

  wrap_wl_surface_commit(surface);
  writeln('wrap_wl_surface_commit');

  while (wl_display_dispatch(display) <> -1) do
    { This space deliberately left blank };

  wl_display_disconnect(display);
  writeln('wl_display_disconnect');
end.
