const STORAGE_KEY = "theme";
const media = window.matchMedia("(prefers-color-scheme: dark)");

export function resolveTheme() {
  return localStorage.getItem(STORAGE_KEY) ?? (media.matches ? "dark" : "light");
}

export function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  localStorage.setItem(STORAGE_KEY, theme);
  return theme;
}

export function toggleTheme() {
  return applyTheme(resolveTheme() === "dark" ? "light" : "dark");
}

// Follow the OS until the user makes an explicit choice.
media.addEventListener("change", (event) => {
  if (!localStorage.getItem(STORAGE_KEY)) {
    document.documentElement.dataset.theme = event.matches ? "dark" : "light";
  }
});
