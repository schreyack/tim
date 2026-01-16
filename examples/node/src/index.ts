/**
 * Application entry point.
 */

import { createApp } from "./app.js";
import { config } from "./config.js";

const app = createApp();

app.listen(config.port, () => {
  console.warn(`Server running on port ${config.port}`);
});
