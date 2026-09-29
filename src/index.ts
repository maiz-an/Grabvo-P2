import { startServer } from "./server";
import { scheduleUpdateChecks } from "./updater";
import { logger } from "./logger";

process.on("uncaughtException", (err) => {
  // Never terminate because of a transient QZ Tray/network error — log
  // and keep listening. Spec: "not terminate because QZ Tray is
  // temporarily unavailable".
  logger.error("Uncaught exception (agent keeps running):", err);
});

process.on("unhandledRejection", (reason) => {
  logger.error("Unhandled rejection (agent keeps running):", reason);
});

startServer();
scheduleUpdateChecks();
