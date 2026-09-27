import express from "express";
import request from "supertest";
import {
  metricsMiddleware,
  metricsHandler,
  healthHandler,
  dbState,
} from "../../src/middlewares/monitoring-middleware";

const buildApp = () => {
  const app = express();
  app.use(metricsMiddleware);
  app.get("/health", healthHandler);
  app.get("/metrics", metricsHandler);
  app.get("/api/items/:id", (req, res) => {
    res.json({ id: req.params.id });
  });
  return app;
};

describe("monitoring middleware", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("GET /health returns 503 when the database is not connected", async () => {
    jest.spyOn(dbState, "isReady").mockReturnValue(false);
    const res = await request(buildApp()).get("/health");
    expect(res.status).toBe(503);
    expect(res.body).toMatchObject({ status: "degraded", db: "disconnected" });
  });

  it("GET /health returns 200 when the database is connected", async () => {
    jest.spyOn(dbState, "isReady").mockReturnValue(true);
    const res = await request(buildApp()).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ status: "ok", db: "connected" });
    expect(typeof res.body.uptimeSeconds).toBe("number");
  });

  it("GET /metrics exposes Prometheus metrics in text format", async () => {
    const res = await request(buildApp()).get("/metrics");
    expect(res.status).toBe(200);
    expect(res.headers["content-type"]).toContain("text/plain");
    expect(res.text).toContain("process_cpu_user_seconds_total");
    expect(res.text).toContain("evat_db_up");
  });

  it("records request counts using the route template, not the raw URL", async () => {
    const app = buildApp();
    await request(app).get("/api/items/123");
    await request(app).get("/api/items/456");
    const res = await request(app).get("/metrics");
    expect(res.text).toMatch(
      /http_requests_total\{method="GET",route="\/api\/items\/:id",status_code="200"[^}]*\} [2-9]/
    );
    expect(res.text).not.toContain('route="/api/items/123"');
  });
});
