import net from "node:net";

import { afterEach, describe, expect, it } from "vitest";

import { IpcSession } from "../src/ipc/session.js";

/**
 * Regression: a failed handshake must close its pipe. PulseService has a fixed
 * number of pipe instances (32); each leaked socket permanently used one until
 * the service reported "pipe slots exhausted".
 */
describe("IpcSession pipe hygiene", () => {
  let server: net.Server | null = null;

  afterEach(async () => {
    await new Promise<void>((resolve) => {
      if (!server) return resolve();
      server.close(() => resolve());
    });
    server = null;
  });

  function startSilentServer(pipeName: string): {
    openSockets: () => number;
    accepted: () => number;
  } {
    const open = new Set<net.Socket>();
    let accepted = 0;
    // Accepts connections but never answers ClientHello.
    server = net.createServer((socket) => {
      accepted += 1;
      open.add(socket);
      // Drain ClientHello so Node emits "end"/"close" when the client hangs up.
      socket.resume();
      socket.on("close", () => open.delete(socket));
      socket.on("error", () => open.delete(socket));
    });
    return { openSockets: () => open.size, accepted: () => accepted };
  }

  it("closes the pipe when ServerHello never arrives", async () => {
    const pipeName = `\\\\.\\pipe\\PulseMcpLeakTest-${process.pid}-${Date.now()}`;
    const fake = startSilentServer(pipeName);
    await new Promise<void>((r) => server!.listen(pipeName, () => r()));

    const session = new IpcSession(pipeName);
    for (let attempt = 0; attempt < 5; attempt += 1) {
      await expect(session.ensureConnected(150)).rejects.toThrow();
    }
    // Let the server observe the client-side closes.
    await new Promise((r) => setTimeout(r, 200));

    expect(fake.accepted()).toBe(5);
    expect(fake.openSockets()).toBe(0);
    await session.close();
  });
});
