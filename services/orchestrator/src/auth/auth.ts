import { FastifyRequest } from "fastify";

import { HttpError } from "../errors";
import { AuthRole, AuthSettings } from "../types";

export interface AuthActor {
  userId: string;
  role: AuthRole;
}

function normalizeHeaderValue(value: string | string[] | undefined): string | undefined {
  if (!value) {
    return undefined;
  }

  if (Array.isArray(value)) {
    return value[0]?.trim() || undefined;
  }

  const trimmed = value.trim();
  return trimmed || undefined;
}

function extractToken(value: string | undefined): string | undefined {
  if (!value) {
    return undefined;
  }

  const bearerPrefix = "bearer ";
  if (value.toLowerCase().startsWith(bearerPrefix)) {
    const token = value.slice(bearerPrefix.length).trim();
    return token || undefined;
  }

  return value;
}

export class AuthService {
  constructor(private readonly settings: AuthSettings) {}

  resolveActor(request: FastifyRequest): AuthActor {
    if (!this.settings.enabled) {
      return {
        userId: this.settings.defaultUserId,
        role: "admin",
      };
    }

    const headerName = this.settings.header.toLowerCase();
    const rawValue = normalizeHeaderValue(request.headers[headerName]);
    const token = extractToken(rawValue);

    if (!token) {
      throw new HttpError(401, `Missing authentication header '${this.settings.header}'`);
    }

    const binding = this.settings.tokens[token];
    if (!binding) {
      throw new HttpError(403, "Invalid authentication token");
    }

    return {
      userId: binding.userId,
      role: binding.role,
    };
  }
}