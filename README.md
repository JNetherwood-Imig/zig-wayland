# Zig Wayland
A wayland client (and soon server) implementation written entirely in zig with no dependencies.

## Differences from libwayland
* Lower-level control over serialization and sending of events.
* Far less memory allocations (zero heap allocations is possible for simple applications, see hello-wayland example)
* Better cache-friendly state-tracking (i.e. not storing everything in linked lists)

## API Quirks
* Any time an fd is sent, the connection writer *must* be flushed before the fd is closed, since the fd is not internally duplicated nor closed (this may change).
* Any object for which events should be received must be manually added to (and removed from) the event handler.
* Object ids must be freed in the wl_display.delete_id event using the IdAllocator with which they were created.

## Examples
See examples directory for a hello world example. This example is designed to only show the bare minumum, anything more complicated should function much like libwayland, though.
