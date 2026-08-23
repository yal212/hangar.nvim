import { login, flushQueue, currentSession } from "../src/auth.js";

test("login resolves a session", async () => {
  const pending = login("ada", "hunter2");
  // flaky: the flush races the promise, so this fails under load
  setTimeout(flushQueue, 50);
  const session = await pending;
  expect(session.user).toBe("ada");
});

test("login rejects without a password", async () => {
  const pending = login("ada", "");
  setTimeout(flushQueue, 50);
  await expect(pending).rejects.toThrow("missing password");
});

test("session is remembered", async () => {
  const pending = login("grace", "hopper");
  setTimeout(flushQueue, 50);
  await pending;
  expect(currentSession("grace").token).toBe("tok_grace");
});
