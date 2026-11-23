"""The lab's one way out: bytes relayed to one host and port, and nowhere else.

    relay.py LISTEN_PORT HOST PORT

It stands on both the lab's closed network and the outside one. The lab reaches the
model's host through it (TLS end to end: the relay sees no key and no content), and has
no other route out.
"""
import asyncio
import sys


async def pump(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        writer.close()


async def main(listen, host, port):
    async def serve(reader, writer):
        try:
            up_reader, up_writer = await asyncio.open_connection(host, port)
        except OSError:
            writer.close()
            return
        await asyncio.gather(pump(reader, up_writer), pump(up_reader, writer))

    server = await asyncio.start_server(serve, "0.0.0.0", listen)
    print(f"relay: {listen} -> {host}:{port}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1]), sys.argv[2], int(sys.argv[3])))
