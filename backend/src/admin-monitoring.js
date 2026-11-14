import { Router } from "express";
import { z } from "zod";
import { jeepneyId } from "./validation.js";

export const monitoringQuery = z
  .object({
    search: z.string().trim().max(120).default(""),
    routeId: z
      .union([z.literal("all"), z.literal("unassigned"), z.string().uuid()])
      .default("all"),
    reporting: z.enum(["all", "fresh", "stale", "missing"]).default("all"),
    status: z.enum(["all", "active", "inactive"]).default("all"),
    device: z
      .enum([
        "all",
        "enabled",
        "disabled",
        "revoked",
        "unprovisioned",
        "unassigned",
      ])
      .default("all"),
    page: z.coerce.number().int().min(1).max(100000).default(1),
    selectedId: jeepneyId.optional(),
  })
  .strict();

export function adminMonitoringRouter({ repository, config, clock }) {
  const router = Router();
  router.get("/monitoring", async (req, res) => {
    const input = monitoringQuery.safeParse(req.query);
    if (!input.success)
      return res.status(400).json({ error: "INVALID_MONITORING_QUERY" });
    res.json({
      data: await repository.snapshot(
        input.data,
        clock(),
        config.STALE_AFTER_SECONDS,
      ),
    });
  });
  return router;
}
