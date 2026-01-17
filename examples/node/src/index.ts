/**
 * Application entry point.
 */

import { createLogger } from "@tim/lib/logging";

import { createApp } from "./app.js";
import { config } from "./config.js";

const logger = createLogger({
  level: config.logLevel,
  serviceName: "example-node-api",
  environment: config.environment,
});

const app = createApp();

app.listen(config.port, () => {
  logger.info({ port: config.port }, "Server started");
});
