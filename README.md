# Zig Wayland
A wayland client (and soon server) implementation written entirely in zig with no dependencies.

## WARNING
This project is not ready to be used, AT ALL. The repo is only public because this is a school project.

## Differences from libwayland
* Lower-level control over serialization and sending of events.
* Far less memory allocations (zero heap allocations is possible for simple applications, see hello-wayland example)
* Better cache-friendly state-tracking (i.e. not storing everything in linked lists)

## API Quirks
* Any time an fd is sent, the connection writer **must** be flushed before the fd is closed, since the fd is not internally duplicated nor closed (this may change).
* Any object for which events should be received must be manually added to (and removed from) the event handler.
* Object ids must be freed in the wl_display.delete_id event using the IdAllocator with which they were created.
* Due to the differences in how zig and libc handle environment variables (mostly due to the problems with the posix spec), support for the WAYLAND_SOCKET environment variable for establishing a connection is very tentative. There does not seem to be a safe way to handle the connection, and it is equally bad to ignore it, so using this API for a client that is likely to be spawned by a parent process that sets WAYLAND_SOCKET is probably not ideal.

## Examples
See examples directory for a hello world example. This example is designed to only show the bare minumum, anything more complicated should function much like libwayland, though.
