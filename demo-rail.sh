#!/bin/bash
# demo-rail.sh — Full Crystl demo: rail tiles, code activity, approval panels, notifications
# Usage: ./demo-rail.sh
#
# Creates 5 demo projects with icons/colors, opens them in Crystl.
# The webapp tab auto-runs a scripted sequence showing code → claude → approval panels.

DEMO_DIR="/tmp/crystl-demo"
BRIDGE="http://127.0.0.1:19280"

rm -rf "$DEMO_DIR"

# ══════════════════════════════════════════
# 1. CREATE DEMO PROJECTS
# ══════════════════════════════════════════

echo "Setting up demo projects..."

# ── webapp ──
dir="$DEMO_DIR/webapp"
mkdir -p "$dir/.crystl" "$dir/src/components" "$dir/src/api"
cat > "$dir/.crystl/project.json" << 'EOF'
{ "color": "#7AA2F7", "icon": "rocket" }
EOF
cat > "$dir/src/components/Dashboard.tsx" << 'SRCEOF'
import React, { useState, useEffect } from 'react';
import { Card, Grid, Metric, Text, AreaChart } from '@tremor/react';
import { fetchAnalytics, AnalyticsData } from '../api/analytics';

interface DashboardProps {
  projectId: string;
  dateRange: [Date, Date];
}

export default function Dashboard({ projectId, dateRange }: DashboardProps) {
  const [data, setData] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    fetchAnalytics(projectId, dateRange)
      .then(setData)
      .finally(() => setLoading(false));
  }, [projectId, dateRange]);

  if (loading) return <Skeleton rows={4} />;

  return (
    <Grid numItems={3} className="gap-6">
      <Card decoration="top" decorationColor="blue">
        <Text>Active Users</Text>
        <Metric>{data?.activeUsers.toLocaleString()}</Metric>
      </Card>
      <Card decoration="top" decorationColor="emerald">
        <Text>Revenue</Text>
        <Metric>${data?.revenue.toLocaleString()}</Metric>
      </Card>
      <Card decoration="top" decorationColor="amber">
        <Text>Conversion Rate</Text>
        <Metric>{data?.conversionRate}%</Metric>
      </Card>
      <AreaChart
        className="h-72 mt-4"
        data={data?.timeline ?? []}
        index="date"
        categories={["pageViews", "uniqueVisitors"]}
        colors={["blue", "cyan"]}
        showAnimation={true}
      />
    </Grid>
  );
}
SRCEOF

cat > "$dir/src/api/analytics.ts" << 'SRCEOF'
export interface AnalyticsData {
  activeUsers: number;
  revenue: number;
  conversionRate: number;
  timeline: { date: string; pageViews: number; uniqueVisitors: number }[];
}

export async function fetchAnalytics(
  projectId: string,
  dateRange: [Date, Date]
): Promise<AnalyticsData> {
  const [start, end] = dateRange.map(d => d.toISOString().split('T')[0]);
  const res = await fetch(`/api/analytics/${projectId}?start=${start}&end=${end}`);
  if (!res.ok) throw new Error(`Analytics fetch failed: ${res.status}`);
  return res.json();
}
SRCEOF

# Autorun script — executed automatically when the webapp tab opens
cat > "$dir/.crystl/autorun.sh" << 'AUTOEOF'
clear
echo ""
cat -n src/components/Dashboard.tsx
sleep 3
echo ""
echo -e "\033[0;36m❯\033[0m \c"
# "Type" the claude command
for c in c l a u d e; do echo -n "$c"; sleep 0.08; done
echo ""
sleep 1.5

echo ""
echo -e "\033[0;90m╭─────────────────────────────────────────────╮\033[0m"
echo -e "\033[0;90m│\033[0m  \033[1;37mClaude Code\033[0m \033[0;90mv1.0.12\033[0m                        \033[0;90m│\033[0m"
echo -e "\033[0;90m│\033[0m  \033[0;90m~/webapp\033[0m                                   \033[0;90m│\033[0m"
echo -e "\033[0;90m╰─────────────────────────────────────────────╯\033[0m"
echo ""
sleep 1

# "Type" a prompt
echo -ne "\033[1;35m❯\033[0m "
prompt="Add error handling with a retry button to the Dashboard component"
for (( i=0; i<${#prompt}; i++ )); do
    echo -n "${prompt:$i:1}"
    sleep 0.025
done
echo ""
sleep 1.5

echo ""
echo -e "\033[0;90m● Reading src/components/Dashboard.tsx...\033[0m"
sleep 0.8
echo -e "\033[0;90m● Analyzing component structure...\033[0m"
sleep 0.6
echo -e "\033[0;90m● Planning changes...\033[0m"
sleep 1

echo ""
echo -e "I'll add error handling with a retry mechanism. This requires:"
echo ""
echo -e "  1. Adding error state and refetch logic to the hook"
echo -e "  2. Creating an \033[1mErrorCard\033[0m component with a retry button"
echo -e "  3. Running the test suite to verify"
echo ""
sleep 0.5
echo -e "\033[0;33m⏳ Waiting for approval...\033[0m"
AUTOEOF

# ── api-server ──
dir="$DEMO_DIR/api-server"
mkdir -p "$dir/.crystl" "$dir/src/routes"
cat > "$dir/.crystl/project.json" << 'EOF'
{ "color": "#F7768E", "icon": "zap" }
EOF
cat > "$dir/src/routes/auth.rs" << 'SRCEOF'
use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use jsonwebtoken::{encode, Header, EncodingKey};
use argon2::{Argon2, PasswordHash, PasswordVerifier};

#[derive(Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
}

pub async fn login(
    State(pool): State<PgPool>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<TokenResponse>, StatusCode> {
    let user = sqlx::query_as!(User, "SELECT * FROM users WHERE email = $1", req.email)
        .fetch_optional(&pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;

    Argon2::default()
        .verify_password(req.password.as_bytes(), &parsed_hash)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let access_token = encode(&Header::default(), &claims, &EncodingKey::from_secret(SECRET))
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(TokenResponse { access_token, refresh_token, expires_in: 3600 }))
}
SRCEOF

# ── design-system ──
dir="$DEMO_DIR/design-system"
mkdir -p "$dir/.crystl" "$dir/src/tokens"
cat > "$dir/.crystl/project.json" << 'EOF'
{ "color": "#BB9AF7", "icon": "gem" }
EOF
cat > "$dir/src/tokens/colors.ts" << 'SRCEOF'
export const palette = {
  blue:   { 50: '#EFF6FF', 500: '#3B82F6', 700: '#1D4ED8', 900: '#1E3A5F' },
  red:    { 50: '#FEF2F2', 500: '#EF4444', 700: '#B91C1C', 900: '#7F1D1D' },
  green:  { 50: '#F0FDF4', 500: '#22C55E', 700: '#15803D', 900: '#14532D' },
  purple: { 50: '#FAF5FF', 500: '#A855F7', 700: '#7E22CE', 900: '#581C87' },
} as const;
SRCEOF

# ── docs ──
dir="$DEMO_DIR/docs"
mkdir -p "$dir/.crystl" "$dir/guides"
cat > "$dir/.crystl/project.json" << 'EOF'
{ "color": "#9ECE6A", "icon": "book" }
EOF
cat > "$dir/guides/getting-started.md" << 'SRCEOF'
# Getting Started

## Quick Start
git clone https://github.com/acme/platform.git
cd platform && pnpm install
pnpm db:migrate && pnpm dev
SRCEOF

# ── infra ──
dir="$DEMO_DIR/infra"
mkdir -p "$dir/.crystl" "$dir/terraform"
cat > "$dir/.crystl/project.json" << 'EOF'
{ "color": "#FF9E64", "icon": "shield" }
EOF
cat > "$dir/terraform/main.tf" << 'SRCEOF'
terraform {
  required_version = ">= 1.5"
  backend "s3" {
    bucket = "acme-terraform-state"
    key    = "prod/platform.tfstate"
  }
}

module "eks" {
  source          = "./modules/eks"
  cluster_name    = "platform-${var.environment}"
  cluster_version = "1.29"
  node_groups = {
    general = { instance_types = ["m6i.xlarge"], min_size = 3, max_size = 10 }
  }
}
SRCEOF

echo "  ✓ 5 projects created"

# ══════════════════════════════════════════
# 2. CONFIGURE BRIDGE FOR DEMO
# ══════════════════════════════════════════

SAVED_SETTINGS=""
if curl -sf "$BRIDGE/health" > /dev/null 2>&1; then
    SAVED_SETTINGS=$(curl -sf "$BRIDGE/settings")
    curl -sf -X POST "$BRIDGE/settings" \
      -H "Content-Type: application/json" \
      -d '{"autoApproveMode":"manual","enabledNotifications":{"Stop":true,"PostToolUse":true,"SubagentStop":true,"TaskCompleted":true,"Notification":true,"TeammateIdle":true,"SessionEnd":true}}' > /dev/null
    echo "  ✓ Bridge set to manual mode"
fi

# ══════════════════════════════════════════
# 3. OPEN PROJECTS IN CRYSTL
# ══════════════════════════════════════════

echo ""
echo "Opening projects..."

# Open webapp first — it has the autorun script
open -a Crystl "$DEMO_DIR/webapp"
sleep 0.5

for name in api-server design-system docs infra; do
    open -a Crystl "$DEMO_DIR/$name"
    sleep 0.3
done

# ══════════════════════════════════════════
# 4. WAIT FOR AUTORUN THEN SEND APPROVALS
# ══════════════════════════════════════════

# The autorun script takes ~14s to reach "Waiting for approval..."
echo "Waiting for terminal sequence..."
sleep 15

if curl -sf "$BRIDGE/health" > /dev/null 2>&1; then
    echo "Sending approval panels..."

    curl -sf -X POST "$BRIDGE/hook?type=PermissionRequest" \
      -H "Content-Type: application/json" \
      -d '{
        "tool_name": "Edit",
        "tool_input": {"file_path": "src/components/Dashboard.tsx", "old_string": "if (loading) return <Skeleton rows={4} />;", "new_string": "if (loading) return <Skeleton rows={4} />;\n  if (error) return <ErrorCard message={error} onRetry={refetch} />;"},
        "cwd": "/tmp/crystl-demo/webapp",
        "session_id": "demo-webapp-001",
        "permission_mode": "default"
      }' > /dev/null &
    sleep 2

    curl -sf -X POST "$BRIDGE/hook?type=PermissionRequest" \
      -H "Content-Type: application/json" \
      -d '{
        "tool_name": "Write",
        "tool_input": {"file_path": "src/components/ErrorCard.tsx", "content": "export function ErrorCard({ message, onRetry }) { ... }"},
        "cwd": "/tmp/crystl-demo/webapp",
        "session_id": "demo-webapp-001",
        "permission_mode": "default"
      }' > /dev/null &
    sleep 2

    curl -sf -X POST "$BRIDGE/hook?type=PermissionRequest" \
      -H "Content-Type: application/json" \
      -d '{
        "tool_name": "Bash",
        "tool_input": {"command": "npm test -- --run src/components/Dashboard.test.tsx"},
        "cwd": "/tmp/crystl-demo/webapp",
        "session_id": "demo-webapp-001",
        "permission_mode": "default"
      }' > /dev/null &

    sleep 3

    # Notifications from other projects
    curl -sf -X POST "$BRIDGE/hook?type=Stop" \
      -H "Content-Type: application/json" \
      -d '{
        "session_id": "demo-api-002",
        "cwd": "/tmp/crystl-demo/api-server",
        "last_assistant_message": "Auth module refactored. JWT refresh token rotation enabled on all endpoints.",
        "stop_hook_active": true
      }' > /dev/null

    sleep 1.5

    curl -sf -X POST "$BRIDGE/hook?type=Stop" \
      -H "Content-Type: application/json" \
      -d '{
        "session_id": "demo-infra-003",
        "cwd": "/tmp/crystl-demo/infra",
        "last_assistant_message": "Terraform plan ready. 3 resources to add, 1 to modify, 0 to destroy.",
        "stop_hook_active": true
      }' > /dev/null

    echo "  ✓ All panels sent"
else
    echo "⚠ Bridge not running — skipping events."
fi

# ══════════════════════════════════════════
# 5. RESTORE BRIDGE SETTINGS
# ══════════════════════════════════════════

if [ -n "$SAVED_SETTINGS" ]; then
    echo ""
    echo "Restoring bridge settings in 15s..."
    sleep 15
    curl -sf -X POST "$BRIDGE/settings" \
      -H "Content-Type: application/json" \
      -d "$SAVED_SETTINGS" > /dev/null
    echo "  ✓ Restored"
fi

echo ""
echo "Demo complete."
