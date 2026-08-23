const sessions = new Map();
const queue = [];

export function flushQueue() {
  while (queue.length) {
    queue.shift()();
  }
}

export function login(user, password) {
  return new Promise((resolve, reject) => {
    queue.push(() => {
      if (!password) {
        reject(new Error("missing password"));
        return;
      }
      const session = { user, token: `tok_${user}` };
      sessions.set(user, session);
      resolve(session);
    });
  });
}

export function currentSession(user) {
  return sessions.get(user) ?? null;
}
