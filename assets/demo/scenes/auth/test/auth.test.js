import { login, flushQueue, currentSession } from "../src/auth.js";

// The queue is drained synchronously right after the promise is created, so the
// test no longer depends on a 50ms timer winning a race with the event loop.
async function settle(pending) {
  flushQueue();
  return pending;
}

test("login resolves a session", async () => {
  const session = await settle(login("ada", "hunter2"));
  expect(session.user).toBe("ada");
});

test("login rejects without a password", async () => {
  await expect(settle(login("ada", ""))).rejects.toThrow("missing password");
});

test("session is remembered", async () => {
  await settle(login("grace", "hopper"));
  expect(currentSession("grace").token).toBe("tok_grace");
});
