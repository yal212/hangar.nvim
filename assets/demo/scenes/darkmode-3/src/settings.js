import { resolveTheme, toggleTheme } from "./theme.js";

export const SETTINGS = {
  language: "en",
  fontSize: 14,
  notifications: true,
};

export function renderSettings(root) {
  root.innerHTML = `
    <section class="panel">
      <h1>Settings</h1>
      <label>Language <input id="language" value="${SETTINGS.language}" /></label>
      <label>Font size <input id="font-size" value="${SETTINGS.fontSize}" /></label>
      <label>Notifications <input id="notifications" type="checkbox" /></label>
      <button id="theme-toggle" type="button">Theme: ${resolveTheme()}</button>
    </section>
  `;
  root.querySelector("#notifications").checked = SETTINGS.notifications;

  const button = root.querySelector("#theme-toggle");
  button.addEventListener("click", () => {
    button.textContent = `Theme: ${toggleTheme()}`;
  });
}
