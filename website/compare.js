// The Light / Dark switch above the screens: shows every screenshot in light or dark.
// Light is the default; the dark ones sit on top and fade in.
const section = document.getElementById("screens");
const buttons = section.querySelectorAll(".mode-toggle button");
buttons.forEach((button) => {
  button.addEventListener("click", () => {
    const dark = button.dataset.mode === "dark";
    section.classList.toggle("show-dark", dark);
    buttons.forEach((b) => b.setAttribute("aria-pressed", String(b === button)));
    // The visible one of each pair of videos plays; they stay in step.
    section.querySelectorAll(".compare").forEach((box) => {
      const [light, darkVideo] = box.querySelectorAll("video");
      if (light && darkVideo) darkVideo.currentTime = light.currentTime;
    });
  });
});
