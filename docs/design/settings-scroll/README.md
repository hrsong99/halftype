# The sidebar under the sky, and one scrolling settings page (round 1)

John, with a screenshot of the dark sidebar full of dots: "How come the pixel art is covering the sidebar? Next, instead of being in different tabs/pages, I want all the settings to be scrollable."

Why the dots are there: `Root` draws the Sky behind the whole window, sidebar included, and the sidebar's only background is `Color.primary.opacity(0.03)`. A side effect of dither-look round 3's "every page sits on the sky", never decided for the sidebar.

- `index.html`: A (today) to F, live mock windows (scroll them, click the sidebar; Dark/Light buttons), plus K–M, Codex image ideas.
- `options.png`: frozen screenshot of A–F, dark.
- `images/`: `K/L/M.jpg`, their `prompts/`, `gen.sh <letter>` to remake one; `today-*.png` were the references.

Options: A today · B solid sidebar as a table of contents, one scroll · C sidebar of two (Try It, Settings) · D no sidebar, a gear · E one scroll for everything · F floating sidebar card on the sky.

Recommendation: B. Pick: (pending)
