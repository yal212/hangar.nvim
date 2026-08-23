export const SETTINGS = {
  language: "en",
  fontSize: 14,
  notifications: true,
  theme: localStorage.getItem("theme") ?? "light",
};

function applyTheme(theme) {
  SETTINGS.theme = theme;
  document.documentElement.dataset.theme = theme;
  localStorage.setItem("theme", theme);
}

export function renderSettings(root) {
  root.innerHTML = `
    <section class="panel">
      <h1>Settings</h1>
      <label>Language <input id="language" value="${SETTINGS.language}" /></label>
      <label>Font size <input id="font-size" value="${SETTINGS.fontSize}" /></label>
      <label>Notifications <input id="notifications" type="checkbox" /></label>
      <label>Dark mode <input id="dark-mode" type="checkbox" /></label>
    </section>
  `;
  root.querySelector("#notifications").checked = SETTINGS.notifications;

  const toggle = root.querySelector("#dark-mode");
  toggle.checked = SETTINGS.theme === "dark";
  toggle.addEventListener("change", () => {
    applyTheme(toggle.checked ? "dark" : "light");
  });

  applyTheme(SETTINGS.theme);
}
