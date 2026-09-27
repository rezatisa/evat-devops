import { Request, Response, NextFunction } from "express";
import mongoose from "mongoose";
import client from "prom-client";

// Wrapped in an object so tests can stub the DB state.
export const dbState = {
  isReady: (): boolean => mongoose.connection.readyState === 1,
};

// Prometheus registry with default Node.js process metrics (CPU, memory, event loop)
export const register = new client.Registry();
register.setDefaultLabels({
  app: "evat-api",
  env: process.env.APP_ENV || "local",
  version: process.env.APP_VERSION || "dev",
});
client.collectDefaultMetrics({ register });

export const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Duration of HTTP requests in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5],
  registers: [register],
});

export const httpRequestsTotal = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "status_code"],
  registers: [register],
});

export const dbUp = new client.Gauge({
  name: "evat_db_up",
  help: "1 if the MongoDB connection is ready, 0 otherwise",
  registers: [register],
  collect() {
    this.set(dbState.isReady() ? 1 : 0);
  },
});

// Use the matched Express route (e.g. /api/vehicle/:id) instead of the raw URL
// so metrics are not exploded by IDs in the path.
const routeLabel = (req: Request): string => {
  if (req.route && req.route.path) {
    return `${req.baseUrl}${req.route.path}`;
  }
  return req.baseUrl || "unmatched";
};

export const metricsMiddleware = (req: Request, res: Response, next: NextFunction) => {
  if (req.path === "/metrics") return next();
  const end = httpRequestDuration.startTimer();
  res.on("finish", () => {
    const labels = {
      method: req.method,
      route: routeLabel(req),
      status_code: String(res.statusCode),
    };
    end(labels);
    httpRequestsTotal.inc(labels);
  });
  next();
};

export const metricsHandler = async (_req: Request, res: Response) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
};

export const healthHandler = (_req: Request, res: Response) => {
  const dbReady = dbState.isReady();
  res.status(dbReady ? 200 : 503).json({
    status: dbReady ? "ok" : "degraded",
    db: dbReady ? "connected" : "disconnected",
    version: process.env.APP_VERSION || "dev",
    env: process.env.APP_ENV || "local",
    uptimeSeconds: Math.round(process.uptime()),
  });
};
