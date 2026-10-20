// Light and dark side by side: the dark screenshot shows left of the handle.
// Drag anywhere on a screenshot (or use the arrow keys on its slider).
document.querySelectorAll(".compare").forEach((box) => {
  const range = box.querySelector(".compare-range");
  const set = (pct) => {
    pct = Math.max(0, Math.min(100, pct));
    box.style.setProperty("--pos", pct + "%");
    range.value = Math.round(pct);
  };
  const fromPointer = (e) => {
    const r = box.getBoundingClientRect();
    set(((e.clientX - r.left) / r.width) * 100);
  };
  box.addEventListener("pointerdown", (e) => {
    box.setPointerCapture(e.pointerId);
    fromPointer(e);
  });
  box.addEventListener("pointermove", (e) => {
    if (box.hasPointerCapture(e.pointerId)) fromPointer(e);
  });
  range.addEventListener("input", () => set(Number(range.value)));
  // Keep the two videos of a screen in step.
  const [light, dark] = box.querySelectorAll("video");
  if (light && dark) {
    light.addEventListener("timeupdate", () => {
      if (Math.abs(dark.currentTime - light.currentTime) > 0.15) dark.currentTime = light.currentTime;
    });
  }
});
