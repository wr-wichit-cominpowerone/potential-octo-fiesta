# wr-wichit-cominpowerone-github-io-
Official Website of Wr-Wichit Cominpowerone - Innovation &amp; Digital Power
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function runUltimateSystem() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "master-controller", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  console.log(`--- กำลังเดินเครื่องระบบ ${"wr-wichit-cominpowerone"} ---`);

  // 1. ส่งข้อมูลอุปกรณ์และวิเคราะห์เสียง
  await client.callTool({
    name: "secure_process_energy",
    arguments: { label: "เครื่องทำความเย็น", watts: 2500, hours: 24, prev_watts: 1800 }
  });

  // 2. ส่งออกรายงานที่บีบอัดแล้ว
  const report = await client.callTool({
    name: "export_compressed_report",
    arguments: {}
  });

  console.log(report.content[0].text);
}

runUltimateSystem().catch(console.error);
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import sqlite3 from "sqlite3";
import { open } from "sqlite";
import fs from "fs";
import zlib from "zlib";
import { promisify } from "util";

const gzip = promisify(zlib.gzip);
const OWNER_ID = "wr-wichit-cominpowerone";
const BUDGET_LIMIT = 3000; // ตั้งงบไว้ที่ 3000 บาท

// --- ส่วนที่ 1: เตรียมฐานข้อมูล SQL ---
const db = await open({
  filename: `${OWNER_ID}_master.db`,
  driver: sqlite3.Database
});

await db.exec(`
  CREATE TABLE IF NOT EXISTS power_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    label TEXT,
    watts REAL,
    hours REAL,
    cost REAL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

// --- ส่วนที่ 2: เริ่มต้น Server ---
const server = new Server({
  name: OWNER_ID,
  version: "5.0.0",
}, {
  capabilities: { tools: {} }
});

// --- ส่วนที่ 3: นิยาม Tools ทั้งหมด ---
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "secure_process_energy",
      description: `ประมวลผลพลังงาน บันทึก SQL และวิเคราะห์เสียงโดย ${OWNER_ID}`,
      inputSchema: {
        type: "object",
        properties: {
          label: { type: "string" },
          watts: { type: "number" },
          hours: { type: "number" },
          prev_watts: { type: "number" }
        },
        required: ["label", "watts", "hours"]
      }
    },
    {
      name: "export_compressed_report",
      description: `สร้างรายงาน CSV และบีบอัดไฟล์ (.gz) โดย ${OWNER_ID}`,
      inputSchema: { type: "object", properties: {} }
    }
  ]
}));

// --- ส่วนที่ 4: ตรรกะการทำงาน (Logic) ---
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "secure_process_energy") {
    const { label, watts, hours, prev_watts = 0 } = args as any;
    const cost = (watts * hours / 1000) * 30 * 4.5;
    
    // บันทึกลงฐานข้อมูล
    await db.run("INSERT INTO power_logs (label, watts, hours, cost) VALUES (?, ?, ?, ?)", [label, watts, hours, cost]);

    // วิเคราะห์จังหวะเสียง (Sound Beat Analysis)
    const isHigh = watts > prev_watts;
    const soundCue = isHigh ? "🔊 [ALERT: HIGH BEAT]" : "🎵 [STABLE: SMOOTH MELODY]";

    return {
      content: [{ 
        type: "text", 
        text: `⭐ [${OWNER_ID} SYSTEM]\nบันทึก: ${label}\nค่าไฟ: ${cost.toFixed(2)} ฿/เดือน\nสถานะเสียง: ${soundCue}`
      }]
    };
  }

  if (name === "export_compressed_report") {
    const rows = await db.all("SELECT * FROM power_logs");
    if (rows.length === 0) return { content: [{ type: "text", text: "ไม่มีข้อมูล" }] };

    let total = 0;
    const csvHeader = `Copyright (c) 2026 ${OWNER_ID}\nID,อุปกรณ์,วัตต์,ชม.,ราคา\n`;
    const csvData = rows.map(r => {
      total += r.cost;
      return `${r.id},${r.label},${r.watts},${r.hours},${r.cost}`;
    }).join("\n");

    const fullContent = "\ufeff" + csvHeader + csvData;
    const compressed = await gzip(Buffer.from(fullContent, "utf-8"));
    
    const fileName = `report_${OWNER_ID}.csv.gz`;
    fs.writeFileSync(fileName, compressed);

    const budgetStatus = total > BUDGET_LIMIT ? "⚠️ OVER BUDGET!" : "✅ UNDER BUDGET";

    return {
      content: [{ 
        type: "text", 
        text: `📦 รายงานสรุปจาก ${OWNER_ID}\nยอดรวม: ${total.toFixed(2)} ฿\nงบประมาณ: ${budgetStatus}\nไฟล์บีบอัด: ${fileName} พร้อมส่ง!`
      }]
    };
  }
  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`>>> ${OWNER_ID} Ultimate Agent is READY <<<`);
{
  "name": "wr-wichit-cominpowerone-ultimate",
  "version": "5.0.0",
  "description": "The Ultimate Power & Sound Management System by wr-wichit-cominpowerone",
  "type": "module",
  "author": "wr-wichit-cominpowerone",
  "scripts": {
    "start-agent": "ts-node --loader ts-node/esm server.ts",
    "run-test": "ts-node --loader ts-node/esm client.ts"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "sqlite3": "^5.1.7",
    "sqlite": "^5.1.1"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "ts-node": "^10.9.0"
  }
}
{
  "name": "acp-demo",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "ts-node": "^10.9.0"
  }
}
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

// 1. สร้าง Instance ของ Server
const server = new Server({
  name: "my-agent",
  version: "1.0.0",
}, {
  capabilities: {
    tools: {} // บอกว่า Agent นี้มีเครื่องมือ (Tools) ให้ใช้
  }
});

// 2. นิยาม Tools ที่ Agent สามารถทำได้
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: "calculate_sum",
    description: "บวกเลขสองจำนวน",
    inputSchema: {
      type: "object",
      properties: {
        a: { type: "number" },
        b: { type: "number" }
      },
      required: ["a", "b"]
    }
  }]
}));

// 3. จัดการเมื่อ Client สั่งรัน Tool
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name === "calculate_sum") {
    const { a, b } = request.params.arguments as { a: number, b: number };
    return {
      content: [{ type: "text", text: `ผลรวมคือ ${a + b}` }]
    };
  }
  throw new Error("Tool not found");
});

// 4. เริ่มการเชื่อมต่อผ่าน Standard I/O
const transport = new StdioServerTransport();
await server.connect(transport);
console.error("Agent Server running...");
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function runClient() {
  // 1. สร้าง Transport เพื่อคุยกับ Server (ผ่านคำสั่งรันไฟล์ server.ts)
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({
    name: "my-client",
    version: "1.0.0"
  }, {
    capabilities: {}
  });

  // 2. เชื่อมต่อ
  await client.connect(transport);

  // 3. ลองเรียกใช้ Tool จาก Server
  const result = await client.callTool({
    name: "calculate_sum",
    arguments: { a: 10, b: 20 }
  });

  console.log("Response from Agent:", result.content[0]);
}

runClient().catch(console.error);
mkdir my-acp-project
cd my-acp-project
npm install
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

// 1. ระบุชื่อเฉพาะของคุณที่นี่: wr-wichit-cominpowerone
const server = new Server({
  name: "wr-wichit-cominpowerone", 
  version: "1.0.0",
}, {
  capabilities: {
    tools: {} 
  }
});

// 2. รายการคำสั่ง (Tools)
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: "get_agent_info",
    description: "แสดงข้อมูลของ Agent ตัวนี้",
    inputSchema: { type: "object", properties: {} }
  }]
}));

// 3. จัดการคำสั่ง
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name === "get_agent_info") {
    return {
      content: [{ 
        type: "text", 
        text: "สวัสดี! ฉันคือ Agent: wr-wichit-cominpowerone พร้อมให้บริการแล้วครับ" 
      }]
    };
  }
  throw new Error("ไม่พบเครื่องมือที่ระบุ");
});

const transport = new StdioServerTransport();
await server.connect(transport);

// ใช้ console.error เพื่อไม่ให้รบกวน protocol
console.error("Agent [wr-wichit-cominpowerone] is now online!");
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function runClient() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({
    name: "main-controller",
    version: "1.0.0"
  }, {
    capabilities: {}
  });

  await client.connect(transport);
  console.log("--- เชื่อมต่อสำเร็จ ---");

  // เรียกใช้ Tool เพื่อยืนยันชื่อ Agent
  const result = await client.callTool({
    name: "get_agent_info",
    arguments: {}
  });

  // แสดงผลลัพธ์ที่ได้จาก wr-wichit-cominpowerone
  console.log("ข้อความจาก Agent:", result.content[0].text);
}

runClient().catch((err) => {
    console.error("เกิดข้อผิดพลาดในการเชื่อมต่อ:", err);
});
npx ts-node --loader ts-node/esm client.ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

// 1. ตั้งค่า Agent: wr-wichit-cominpowerone
const server = new Server({
  name: "wr-wichit-cominpowerone", 
  version: "1.0.0",
}, {
  capabilities: {
    tools: {} 
  }
});

// 2. นิยามความสามารถ (Tools)
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "get_agent_info",
      description: "แสดงข้อมูลของ Agent",
      inputSchema: { type: "object", properties: {} }
    },
    {
      name: "calculate_energy_cost",
      description: "คำนวณค่าไฟจากวัตต์และชั่วโมงที่ใช้",
      inputSchema: {
        type: "object",
        properties: {
          watts: { type: "number", description: "กำลังไฟฟ้า (Watts)" },
          hours: { type: "number", description: "จำนวนชั่วโมงที่ใช้งานต่อวัน" },
          unit_price: { type: "number", description: "ราคาต่อหน่วย (บาท)", default: 4.5 }
        },
        required: ["watts", "hours"]
      }
    }
  ]
}));

// 3. ส่วนประมวลผลคำสั่ง
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "get_agent_info") {
    return {
      content: [{ type: "text", text: "สวัสดี! ฉันคือ Agent: wr-wichit-cominpowerone ยินดีที่ได้ช่วยเรื่องพลังงานครับ" }]
    };
  }

  if (name === "calculate_energy_cost") {
    const watts = args?.watts as number;
    const hours = args?.hours as number;
    const unitPrice = (args?.unit_price as number) || 4.5;

    // สูตร: (Watt * Hour / 1000) * UnitPrice
    const dailyUnit = (watts * hours) / 1000;
    const monthlyCost = dailyUnit * 30 * unitPrice;

    return {
      content: [{ 
        type: "text", 
        text: `[wr-wichit-cominpowerone วิเคราะห์]: อุปกรณ์ ${watts}W ใช้ ${hours} ชม./วัน ค่าไฟประมาณ ${monthlyCost.toFixed(2)} บาทต่อเดือน` 
      }]
    };
  }

  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("Agent [wr-wichit-cominpowerone] พร้อมทำงาน...");
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function main() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "power-tester", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  console.log("--- เริ่มการวิเคราะห์พลังงาน ---");

  // ตัวอย่าง: คำนวณค่าไฟแอร์ 1200 วัตต์ เปิด 8 ชั่วโมง
  const powerResult = await client.callTool({
    name: "calculate_energy_cost",
    arguments: {
      watts: 1200,
      hours: 8,
      unit_price: 4.7
    }
  });

  console.log(powerResult.content[0].text);
}

main().catch(console.error);
npx ts-node --loader ts-node/esm client.ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import fs from "fs"; // เพิ่มโมดูลระบบไฟล์

const server = new Server({
  name: "wr-wichit-cominpowerone", 
  version: "1.0.0",
}, {
  capabilities: { tools: {} }
});

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "calculate_and_save",
      description: "คำนวณค่าไฟและบันทึกลงไฟล์ history",
      inputSchema: {
        type: "object",
        properties: {
          watts: { type: "number" },
          hours: { type: "number" },
          label: { type: "string", description: "ชื่ออุปกรณ์ เช่น 'แอร์ห้องนอน'" }
        },
        required: ["watts", "hours", "label"]
      }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "calculate_and_save") {
    const { watts, hours, label } = args as { watts: number, hours: number, label: string };
    
    // คำนวณ
    const dailyUnit = (watts * hours) / 1000;
    const monthlyCost = dailyUnit * 30 * 4.5;
    const timestamp = new Date().toLocaleString("th-TH");

    const logEntry = `[${timestamp}] ${label}: ${watts}W, ${hours}ชม./วัน -> ค่าไฟประมาณ ${monthlyCost.toFixed(2)} บาท/เดือน\n`;

    // บันทึกลงไฟล์ (Append mode)
    try {
      fs.appendFileSync("power_history.txt", logEntry);
      return {
        content: [{ 
          type: "text", 
          text: `✅ บันทึกเรียบร้อย: ${logEntry}` 
        }]
      };
    } catch (error) {
      return {
        content: [{ type: "text", text: `❌ เกิดข้อผิดพลาดในการเขียนไฟล์: ${error}` }],
        isError: true
      };
    }
  }
  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("Agent [wr-wichit-cominpowerone] พร้อมบันทึกข้อมูล...");
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function main() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "power-tester", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  console.log("--- กำลังส่งข้อมูลให้ wr-wichit-cominpowerone ---");

  // ลองบันทึกอุปกรณ์ที่ 1
  const res1 = await client.callTool({
    name: "calculate_and_save",
    arguments: { label: "ตู้เย็น", watts: 150, hours: 24 }
  });
  console.log(res1.content[0].text);

  // ลองบันทึกอุปกรณ์ที่ 2
  const res2 = await client.callTool({
    name: "calculate_and_save",
    arguments: { label: "คอมพิวเตอร์เกมมิ่ง", watts: 500, hours: 5 }
  });
  console.log(res2.content[0].text);
}

main().catch(console.error);
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import fs from "fs";

const server = new Server({
  name: "wr-wichit-cominpowerone", 
  version: "1.0.0",
}, {
  capabilities: { tools: {} }
});

// 1. เพิ่ม Tool "summarize_history" เข้าไปในรายการ
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "calculate_and_save",
      description: "คำนวณค่าไฟและบันทึกลงไฟล์",
      inputSchema: {
        type: "object",
        properties: {
          watts: { type: "number" },
          hours: { type: "number" },
          label: { type: "string" }
        },
        required: ["watts", "hours", "label"]
      }
    },
    {
      name: "summarize_history",
      description: "อ่านประวัติทั้งหมดและสรุปค่าใช้จ่ายรวม",
      inputSchema: { type: "object", properties: {} }
    }
  ]
}));

// 2. ส่วนประมวลผล (Logic)
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  // --- Tool เดิม: บันทึกข้อมูล ---
  if (name === "calculate_and_save") {
    const { watts, hours, label } = args as { watts: number, hours: number, label: string };
    const dailyUnit = (watts * hours) / 1000;
    const monthlyCost = dailyUnit * 30 * 4.5;
    const logEntry = `${label}|${monthlyCost.toFixed(2)}\n`; // เก็บแบบง่ายๆ เพื่อให้อ่านกลับมาคำนวณง่าย

    fs.appendFileSync("power_history.txt", logEntry);
    return { content: [{ type: "text", text: `💾 บันทึก ${label} เรียบร้อยแล้ว!` }] };
  }

  // --- Tool ใหม่: อ่านและสรุปผล ---
  if (name === "summarize_history") {
    if (!fs.existsSync("power_history.txt")) {
      return { content: [{ type: "text", text: "ยังไม่มีประวัติข้อมูลในระบบครับ" }] };
    }

    const data = fs.readFileSync("power_history.txt", "utf-8");
    const lines = data.trim().split("\n");
    let totalCost = 0;
    let itemsCount = 0;

    lines.forEach(line => {
      const [label, cost] = line.split("|");
      if (cost) {
        totalCost += parseFloat(cost);
        itemsCount++;
      }
    });

    return {
      content: [{ 
        type: "text", 
        text: `📊 [สรุปโดย wr-wichit-cominpowerone]\n--------------------------\nพบข้อมูลอุปกรณ์: ${itemsCount} รายการ\nค่าไฟรวมทั้งหมด: ${totalCost.toFixed(2)} บาท/เดือน` 
      }]
    };
  }

  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("Agent [wr-wichit-cominpowerone] พร้อมสรุปรายงาน...");
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function main() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "power-tester", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  // 1. ลองสั่งสรุปผลข้อมูลที่มีอยู่ในไฟล์
  console.log("--- กำลังเรียกดูรายงานสรุป ---");
  const summary = await client.callTool({
    name: "summarize_history",
    arguments: {}
  });

  console.log(summary.content[0].text);
}

main().catch(console.error);
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import fs from "fs";

const server = new Server({
  name: "wr-wichit-cominpowerone", 
  version: "1.0.0",
}, {
  capabilities: { tools: {} }
});

const DB_FILE = "power_history.txt";
const CSV_FILE = "energy_report.csv";

// --- 1. นิยาม Tools ทั้งหมด ---
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "calculate_and_save",
      description: "คำนวณและบันทึกข้อมูล",
      inputSchema: {
        type: "object",
        properties: {
          watts: { type: "number" },
          hours: { type: "number" },
          label: { type: "string" }
        },
        required: ["watts", "hours", "label"]
      }
    },
    {
      name: "export_to_csv",
      description: "ส่งออกข้อมูลทั้งหมดเป็นไฟล์ CSV สำหรับ Excel",
      inputSchema: { type: "object", properties: {} }
    },
    {
      name: "clear_history",
      description: "ล้างข้อมูลประวัติทั้งหมด",
      inputSchema: { type: "object", properties: {} }
    }
  ]
}));

// --- 2. ส่วนประมวลผลคำสั่ง ---
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  // บันทึกข้อมูล
  if (name === "calculate_and_save") {
    const { watts, hours, label } = args as { watts: number, hours: number, label: string };
    const monthlyCost = (watts * hours / 1000) * 30 * 4.5;
    const timestamp = new Date().toLocaleDateString("th-TH");
    const logEntry = `${timestamp}|${label}|${watts}|${hours}|${monthlyCost.toFixed(2)}\n`;

    fs.appendFileSync(DB_FILE, logEntry);
    return { content: [{ type: "text", text: `✅ บันทึก ${label} เรียบร้อย!` }] };
  }

  // ส่งออกเป็น CSV
  if (name === "export_to_csv") {
    if (!fs.existsSync(DB_FILE)) return { content: [{ type: "text", text: "ไม่มีข้อมูลให้ส่งออก" }] };

    const data = fs.readFileSync(DB_FILE, "utf-8");
    const csvHeader = "วันที่,ชื่ออุปกรณ์,กำลังไฟ(วัตต์),ชั่วโมงต่อวัน,ค่าไฟต่อเดือน(บาท)\n";
    const csvRows = data.trim().split("\n").map(line => line.replace(/\|/g, ",")).join("\n");

    fs.writeFileSync(CSV_FILE, "\ufeff" + csvHeader + csvRows); // เติม BOM เพื่อให้ Excel อ่านภาษาไทยออก
    return { content: [{ type: "text", text: `📊 ส่งออกไฟล์ ${CSV_FILE} สำเร็จ! คุณสามารถเปิดด้วย Excel ได้เลย` }] };
  }

  // ล้างข้อมูล
  if (name === "clear_history") {
    if (fs.existsSync(DB_FILE)) fs.unlinkSync(DB_FILE);
    if (fs.existsSync(CSV_FILE)) fs.unlinkSync(CSV_FILE);
    return { content: [{ type: "text", text: "🗑️ ล้างข้อมูลประวัติทั้งหมดเรียบร้อยแล้ว" }] };
  }

  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("Agent [wr-wichit-cominpowerone] Full Feature พร้อมทำงาน!");
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function main() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "power-tester", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  console.log("--- เริ่มการทำงานของ wr-wichit-cominpowerone ---");

  // 1. เพิ่มข้อมูลตัวอย่าง
  await client.callTool({ name: "calculate_and_save", arguments: { label: "พัดลม", watts: 50, hours: 12 } });
  await client.callTool({ name: "calculate_and_save", arguments: { label: "ทีวี", watts: 100, hours: 4 } });

  // 2. สั่งส่งออกเป็น CSV
  const exportRes = await client.callTool({ name: "export_to_csv", arguments: {} });
  console.log(exportRes.content[0].text);

  // หมายเหตุ: หากต้องการล้างข้อมูล ให้ใช้โค้ดบรรทัดล่างนี้:
  // await client.callTool({ name: "clear_history", arguments: {} });
}

main().catch(console.error);
{
  "name": "wr-wichit-cominpowerone",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "start-agent": "ts-node --loader ts-node/esm server.ts",
    "run-test": "ts-node --loader ts-node/esm client.ts"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "ts-node": "^10.9.0"
  }
}
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import fs from "fs";

// สร้าง Server ในชื่อที่คุณกำหนด
const server = new Server({
  name: "wr-wichit-cominpowerone",
  version: "1.0.0",
}, {
  capabilities: { tools: {} }
});

const DB_FILE = "power_history.txt";
const CSV_FILE = "energy_report.csv";

// --- รวมคำสั่ง (Tools) ทั้งหมดที่ Agent ทำได้ ---
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "calculate_and_save",
      description: "คำนวณค่าไฟและบันทึกลงฐานข้อมูล",
      inputSchema: {
        type: "object",
        properties: {
          watts: { type: "number" },
          hours: { type: "number" },
          label: { type: "string" }
        },
        required: ["watts", "hours", "label"]
      }
    },
    {
      name: "get_summary_report",
      description: "สรุปรายงานการใช้พลังงานทั้งหมดและส่งออกเป็น CSV",
      inputSchema: { type: "object", properties: {} }
    },
    {
      name: "clear_all_data",
      description: "ลบข้อมูลประวัติทั้งหมดเพื่อเริ่มใหม่",
      inputSchema: { type: "object", properties: {} }
    }
  ]
}));

// --- ส่วนประมวลผลตรรกะ (Logic) ---
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case "calculate_and_save": {
      const { watts, hours, label } = args as { watts: number, hours: number, label: string };
      const cost = (watts * hours / 1000) * 30 * 4.5;
      const date = new Date().toLocaleDateString("th-TH");
      fs.appendFileSync(DB_FILE, `${date}|${label}|${watts}|${hours}|${cost.toFixed(2)}\n`);
      return { content: [{ type: "text", text: `[PowerOne] บันทึก ${label} เรียบร้อย (ค่าไฟประมาณ ${cost.toFixed(2)} บาท/เดือน)` }] };
    }

    case "get_summary_report": {
      if (!fs.existsSync(DB_FILE)) return { content: [{ type: "text", text: "ยังไม่มีข้อมูลในระบบ" }] };
      const raw = fs.readFileSync(DB_FILE, "utf-8").trim().split("\n");
      let total = 0;
      const csvContent = raw.map(line => {
        const parts = line.split("|");
        total += parseFloat(parts[4]);
        return parts.join(",");
      }).join("\n");
      
      const header = "วันที่,อุปกรณ์,วัตต์,ชม./วัน,ค่าไฟ/เดือน\n";
      fs.writeFileSync(CSV_FILE, "\ufeff" + header + csvContent);
      return { content: [{ type: "text", text: `📊 สรุปเสร็จสิ้น! ค่าไฟรวม: ${total.toFixed(2)} บาท/เดือน (สร้างไฟล์ CSV แล้ว)` }] };
    }

    case "clear_all_data": {
      if (fs.existsSync(DB_FILE)) fs.unlinkSync(DB_FILE);
      if (fs.existsSync(CSV_FILE)) fs.unlinkSync(CSV_FILE);
      return { content: [{ type: "text", text: "🗑️ ล้างข้อมูลทั้งหมดในระบบ wr-wichit-cominpowerone เรียบร้อย" }] };
    }

    default:
      throw new Error("ไม่พบคำสั่งนี้");
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(">>> wr-wichit-cominpowerone Agent is Active <<<");
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function runSystem() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "controller", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  console.log("🚀 กำลังส่งชุดคำสั่งให้ Agent...");

  // 1. เพิ่มข้อมูลอุปกรณ์ต่างๆ
  await client.callTool({ name: "calculate_and_save", arguments: { label: "เครื่องซักผ้า", watts: 2000, hours: 1 } });
  await client.callTool({ name: "calculate_and_save", arguments: { label: "หลอดไฟ LED", watts: 10, hours: 12 } });

  // 2. เรียกสรุปผลและสร้าง CSV
  const report = await client.callTool({ name: "get_summary_report", arguments: {} });
  console.log(report.content[0].text);
}

runSystem().catch(console.error);
npm install
npm run run-test
{
  "name": "wr-wichit-cominpowerone-agent",
  "version": "1.0.0",
  "description": "Secure Power Management System by wr-wichit-cominpowerone",
  "type": "module",
  "author": "wr-wichit-cominpowerone",
  "scripts": {
    "start": "ts-node --loader ts-node/esm server.ts",
    "test": "ts-node --loader ts-node/esm client.ts"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "ts-node": "^10.9.0"
  }
}
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import fs from "fs";

// ลายน้ำดิจิทัลเพื่อป้องกันการปลอมแปลง
const OWNER_ID = "wr-wichit-cominpowerone";

const server = new Server({
  name: OWNER_ID, // ชื่อ Agent หลัก
  version: "1.0.0",
}, {
  capabilities: { tools: {} }
});

const DB_FILE = `history_${OWNER_ID}.txt`;
const CSV_FILE = `report_${OWNER_ID}.csv`;

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "secure_calculate_save",
      description: `คำนวณและบันทึกข้อมูลภายใต้ลิขสิทธิ์ของ ${OWNER_ID}`,
      inputSchema: {
        type: "object",
        properties: {
          watts: { type: "number" },
          hours: { type: "number" },
          label: { type: "string" }
        },
        required: ["watts", "hours", "label"]
      }
    },
    {
      name: "get_certified_report",
      description: "ออกรายงานสรุปที่มีลายน้ำรับรอง",
      inputSchema: { type: "object", properties: {} }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "secure_calculate_save") {
    const { watts, hours, label } = args as { watts: number, hours: number, label: string };
    const cost = (watts * hours / 1000) * 30 * 4.5;
    const timestamp = new Date().toLocaleString("th-TH");
    
    // บันทึกข้อมูลพร้อมลายน้ำในทุกบรรทัด
    const entry = `${timestamp}|${label}|${watts}|${hours}|${cost.toFixed(2)}|VerifiedBy-${OWNER_ID}\n`;
    fs.appendFileSync(DB_FILE, entry);
    
    return { 
      content: [{ type: "text", text: `[${OWNER_ID}] บันทึกสำเร็จ: ${label} (รับรองข้อมูลถูกต้อง)` }] 
    };
  }

  if (name === "get_certified_report") {
    if (!fs.existsSync(DB_FILE)) return { content: [{ type: "text", text: "ไม่พบข้อมูลในระบบ" }] };

    const rawData = fs.readFileSync(DB_FILE, "utf-8").trim().split("\n");
    let totalCost = 0;
    
    // สร้างหัวไฟล์ CSV พร้อมการประกาศลิขสิทธิ์
    const csvHeader = `Copyright (c) 2026 ${OWNER_ID}\nวันที่,อุปกรณ์,วัตต์,ชม.,ค่าไฟ,สถานะการตรวจสอบ\n`;
    const csvRows = rawData.map(line => {
      const p = line.split("|");
      totalCost += parseFloat(p[4]);
      return p.join(",");
    }).join("\n");

    fs.writeFileSync(CSV_FILE, "\ufeff" + csvHeader + csvRows);
    
    return { 
      content: [{ 
        type: "text", 
        text: `📊 รายงานโดย ${OWNER_ID}\nรวมค่าไฟ: ${totalCost.toFixed(2)} บาท/เดือน\nไฟล์ ${CSV_FILE} ถูกสร้างพร้อมลายน้ำรับรองแล้ว` 
      }] 
    };
  }
  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`>>> ${OWNER_ID} System is now SECURE and ONLINE <<<`);
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function runSecureSystem() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ 
    name: "wr-wichit-cominpowerone-client", 
    version: "1.0.0" 
  }, { capabilities: {} });

  await client.connect(transport);
  console.log(`--- เชื่อมต่อกับระบบของ wr-wichit-cominpowerone สำเร็จ ---`);

  // บันทึกข้อมูลตัวอย่าง
  await client.callTool({
    name: "secure_calculate_save",
    arguments: { label: "เซิร์ฟเวอร์", watts: 800, hours: 24 }
  });

  // เรียกรายงานที่ผ่านการรับรอง
  const report = await client.callTool({ name: "get_certified_report", arguments: {} });
  console.log(report.content[0].text);
}

runSecureSystem().catch(console.error);
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import fs from "fs";
import zlib from "zlib"; // เพิ่มโมดูลบีบอัดไฟล์
import { promisify } from "util";

const gzip = promisify(zlib.gzip);
const OWNER_ID = "wr-wichit-cominpowerone";

const server = new Server({
  name: OWNER_ID,
  version: "1.0.0",
}, {
  capabilities: { tools: {} }
});

const DB_FILE = `history_${OWNER_ID}.txt`;
const CSV_FILE = `report_${OWNER_ID}.csv`;
const ZIP_FILE = `report_${OWNER_ID}.csv.gz`;

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "secure_calculate_save",
      description: `คำนวณและบันทึกข้อมูลโดย ${OWNER_ID}`,
      inputSchema: {
        type: "object",
        properties: {
          watts: { type: "number" },
          hours: { type: "number" },
          label: { type: "string" }
        },
        required: ["watts", "hours", "label"]
      }
    },
    {
      name: "compress_and_export",
      description: `สร้างไฟล์ CSV และบีบอัดไฟล์ (.gz) รับรองโดย ${OWNER_ID}`,
      inputSchema: { type: "object", properties: {} }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "secure_calculate_save") {
    const { watts, hours, label } = args as { watts: number, hours: number, label: string };
    const cost = (watts * hours / 1000) * 30 * 4.5;
    const timestamp = new Date().toLocaleString("th-TH");
    const entry = `${timestamp}|${label}|${watts}|${hours}|${cost.toFixed(2)}|VerifiedBy-${OWNER_ID}\n`;
    fs.appendFileSync(DB_FILE, entry);
    return { content: [{ type: "text", text: `[${OWNER_ID}] บันทึก ${label} แล้ว` }] };
  }

  if (name === "compress_and_export") {
    if (!fs.existsSync(DB_FILE)) return { content: [{ type: "text", text: "ไม่มีข้อมูลให้บีบอัด" }] };

    // 1. สร้างเนื้อหา CSV
    const rawData = fs.readFileSync(DB_FILE, "utf-8").trim().split("\n");
    const header = `Copyright (c) 2026 ${OWNER_ID}\nวันที่,อุปกรณ์,วัตต์,ชม.,ค่าไฟ,สถานะ\n`;
    const csvContent = "\ufeff" + header + rawData.map(line => line.replace(/\|/g, ",")).join("\n");
    
    // 2. เขียนไฟล์ CSV ปกติก่อน
    fs.writeFileSync(CSV_FILE, csvContent);

    // 3. เริ่มกระบวนการบีบอัด (Compression)
    try {
      const buffer = Buffer.from(csvContent, "utf-8");
      const compressed = await gzip(buffer);
      fs.writeFileSync(ZIP_FILE, compressed);

      return {
        content: [{ 
          type: "text", 
          text: `📦 [${OWNER_ID} Compression Service]\n- สร้างไฟล์: ${CSV_FILE}\n- บีบอัดสำเร็จ: ${ZIP_FILE}\nสถานะ: ปลอดภัยและประหยัดพื้นที่!` 
        }]
      };
    } catch (error) {
      return { content: [{ type: "text", text: `❌ บีบอัดล้มเหลว: ${error}` }], isError: true };
    }
  }
  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`>>> ${OWNER_ID} Compression Engine Ready <<<`);
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function run() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "wr-wichit-cominpowerone-client", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  console.log(`--- กำลังทำงานร่วมกับระบบ ${"wr-wichit-cominpowerone"} ---`);

  // บันทึกข้อมูลเพิ่มความแน่นของไฟล์
  await client.callTool({ name: "secure_calculate_save", arguments: { label: "ระบบระบายความร้อน", watts: 1500, hours: 24 } });

  // สั่งบีบอัดไฟล์
  const result = await client.callTool({ name: "compress_and_export", arguments: {} });
  console.log(result.content[0].text);
}

run().catch(console.error);
npm run test
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import fs from "fs";
import zlib from "zlib";
import { promisify } from "util";

const gzip = promisify(zlib.gzip);
const OWNER_ID = "wr-wichit-cominpowerone";
const BUDGET_LIMIT = 5000; // ตั้งงบค่าไฟไว้ที่ 5,000 บาท

const server = new Server({
  name: OWNER_ID,
  version: "1.0.0",
}, {
  capabilities: { tools: {} }
});

const DB_FILE = `history_${OWNER_ID}.txt`;
const ZIP_FILE = `report_${OWNER_ID}.csv.gz`;

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "secure_calculate_save",
      description: `คำนวณและบันทึกข้อมูลโดย ${OWNER_ID}`,
      inputSchema: {
        type: "object",
        properties: {
          watts: { type: "number" },
          hours: { type: "number" },
          label: { type: "string" }
        },
        required: ["watts", "hours", "label"]
      }
    },
    {
      name: "finalize_and_send_report",
      description: `บีบอัดไฟล์และจำลองการส่งรายงานอีเมลโดย ${OWNER_ID}`,
      inputSchema: { type: "object", properties: {} }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "secure_calculate_save") {
    const { watts, hours, label } = args as { watts: number, hours: number, label: string };
    const cost = (watts * hours / 1000) * 30 * 4.5;
    const timestamp = new Date().toLocaleString("th-TH");
    const entry = `${timestamp}|${label}|${watts}|${hours}|${cost.toFixed(2)}|VerifiedBy-${OWNER_ID}\n`;
    fs.appendFileSync(DB_FILE, entry);
    return { content: [{ type: "text", text: `[${OWNER_ID}] บันทึก ${label} สำเร็จ!` }] };
  }

  if (name === "finalize_and_send_report") {
    if (!fs.existsSync(DB_FILE)) return { content: [{ type: "text", text: "ไม่พบข้อมูล" }] };

    const rawData = fs.readFileSync(DB_FILE, "utf-8").trim().split("\n");
    let totalMonthlyCost = 0;
    
    const csvContent = rawData.map(line => {
      const p = line.split("|");
      totalMonthlyCost += parseFloat(p[4]);
      return p.join(",");
    }).join("\n");

    // 1. บีบอัดไฟล์
    const buffer = Buffer.from("\ufeff" + csvContent, "utf-8");
    const compressed = await gzip(buffer);
    fs.writeFileSync(ZIP_FILE, compressed);

    // 2. ระบบวิเคราะห์งบประมาณ (Budget Alert)
    let alertStatus = "✅ อยู่ในงบประมาณ";
    if (totalMonthlyCost > BUDGET_LIMIT) {
      alertStatus = `⚠️ คำเตือน: ค่าไฟเกินงบที่ตั้งไว้ (${BUDGET_LIMIT} บาท)!`;
    }

    // 3. จำลองการส่งอีเมล (Simulation)
    const emailSummary = `
📧 [AUTO-MAIL FROM ${OWNER_ID}]
--------------------------------------
เรียน ผู้จัดการระบบ,
รายงานพลังงานประจำเดือนพร้อมใช้งานแล้ว

สรุปยอดรวม: ${totalMonthlyCost.toFixed(2)} บาท
สถานะงบประมาณ: ${alertStatus}
ไฟล์แนบ: ${ZIP_FILE} (Compressed)

ตรวจสอบโดย: ${OWNER_ID} (Certified)
--------------------------------------
    `;

    return {
      content: [{ type: "text", text: emailSummary }]
    };
  }
  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`>>> ${OWNER_ID} Advanced Mail System Ready <<<`);
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function startPowerOne() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "controller", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  console.log(`--- กำลังเข้าถึงระบบความปลอดภัยของ wr-wichit-cominpowerone ---`);

  // เพิ่มข้อมูลที่กินไฟสูงเพื่อทดสอบระบบ Alert
  await client.callTool({ name: "secure_calculate_save", arguments: { label: "เครื่องจักรโรงงาน A", watts: 15000, hours: 10 } });

  // สั่งจบงาน บีบอัด และส่งรายงาน
  const result = await client.callTool({ name: "finalize_and_send_report", arguments: {} });
  console.log(result.content[0].text);
}

startPowerOne().catch(console.error);
npm run test
{
  "name": "wr-wichit-cominpowerone-ultimate",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "sqlite3": "^5.1.7",
    "sqlite": "^5.1.1"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "ts-node": "^10.9.0"
  }
}
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import sqlite3 from "sqlite3";
import { open } from "sqlite";

const OWNER_ID = "wr-wichit-cominpowerone";

// 1. เชื่อมต่อและสร้างฐานข้อมูล SQLite
const db = await open({
  filename: `${OWNER_ID}_database.db`,
  driver: sqlite3.Database
});

// สร้างตารางถ้ายังไม่มี
await db.exec(`
  CREATE TABLE IF NOT EXISTS energy_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    label TEXT,
    watts REAL,
    hours REAL,
    monthly_cost REAL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    verified_by TEXT
  )
`);

const server = new Server({
  name: OWNER_ID,
  version: "2.0.0",
}, {
  capabilities: { tools: {} }
});

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "db_save_energy",
      description: `บันทึกข้อมูลลงฐานข้อมูล SQL โดย ${OWNER_ID}`,
      inputSchema: {
        type: "object",
        properties: {
          label: { type: "string" },
          watts: { type: "number" },
          hours: { type: "number" }
        },
        required: ["label", "watts", "hours"]
      }
    },
    {
      name: "get_powerone_dashboard",
      description: `แสดงแดชบอร์ดสรุปผลการใช้พลังงานของ ${OWNER_ID}`,
      inputSchema: { type: "object", properties: {} }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "db_save_energy") {
    const { label, watts, hours } = args as { label: string, watts: number, hours: number };
    const cost = (watts * hours / 1000) * 30 * 4.5;

    await db.run(
      "INSERT INTO energy_logs (label, watts, hours, monthly_cost, verified_by) VALUES (?, ?, ?, ?, ?)",
      [label, watts, hours, cost, OWNER_ID]
    );

    return { content: [{ type: "text", text: `⭐ [${OWNER_ID}] ข้อมูลถูกจัดเก็บลง SQL Database เรียบร้อยแล้ว` }] };
  }

  if (name === "get_powerone_dashboard") {
    const rows = await db.all("SELECT * FROM energy_logs");
    const stats = await db.get("SELECT SUM(monthly_cost) as total, COUNT(*) as count FROM energy_logs");

    let table = `\n📊 DASHBOARD: ${OWNER_ID}\n`;
    table += `--------------------------------------------------\n`;
    table += `ID | อุปกรณ์ | วัตต์ | ชม./วัน | ค่าไฟ/เดือน\n`;
    table += `--------------------------------------------------\n`;
    
    rows.forEach(row => {
      table += `${row.id} | ${row.label} | ${row.watts}W | ${row.hours}h | ${row.monthly_cost.toFixed(2)} ฿\n`;
    });

    table += `--------------------------------------------------\n`;
    table += `ยอดรวมอุปกรณ์: ${stats.count} รายการ\n`;
    table += `ประมาณการค่าไฟสุทธิ: ${stats.total?.toFixed(2) || 0} บาท/เดือน\n`;
    table += `สถานะ: ข้อมูลผ่านการรับรองโดย ${OWNER_ID}\n`;

    return { content: [{ type: "text", text: table }] };
  }

  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`>>> ${OWNER_ID} SQL Engine & Dashboard Ready <<<`);
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function run() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "controller", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  console.log(`--- เชื่อมต่อฐานข้อมูลของ ${"wr-wichit-cominpowerone"} ---`);

  // 1. เพิ่มข้อมูลใหม่ลง Database
  await client.callTool({ name: "db_save_energy", arguments: { label: "ตู้แช่แข็ง", watts: 1200, hours: 24 } });
  await client.callTool({ name: "db_save_energy", arguments: { label: "ระบบไฟสนาม", watts: 300, hours: 10 } });

  // 2. เรียกดู Dashboard
  const dashboard = await client.callTool({ name: "get_powerone_dashboard", arguments: {} });
  console.log(dashboard.content[0].text);
}

run().catch(console.error);
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import sqlite3 from "sqlite3";
import { open } from "sqlite";

const OWNER_ID = "wr-wichit-cominpowerone";
const SECRET_KEY = "powerone-1234"; // รหัสผ่านจำลองสำหรับการเข้าถึงระบบ

// เชื่อมต่อฐานข้อมูล SQL
const db = await open({
  filename: `${OWNER_ID}_secure_v3.db`,
  driver: sqlite3.Database
});

await db.exec(`
  CREATE TABLE IF NOT EXISTS secure_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT,
    label TEXT,
    cost REAL,
    status TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

const server = new Server({ name: OWNER_ID, version: "3.0.0" }, { capabilities: { tools: {} } });

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "secure_login_and_notify",
      description: `เข้าระบบและส่งแจ้งเตือน Line โดย ${OWNER_ID}`,
      inputSchema: {
        type: "object",
        properties: {
          user_id: { type: "string" },
          key: { type: "string" },
          label: { type: "string" },
          watts: { type: "number" },
          hours: { type: "number" }
        },
        required: ["user_id", "key", "label", "watts", "hours"]
      }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "secure_login_and_notify") {
    const { user_id, key, label, watts, hours } = args as any;

    // 1. ระบบตรวจสอบสิทธิ์ (Authentication)
    if (key !== SECRET_KEY) {
      return { content: [{ type: "text", text: `❌ รหัสผ่านไม่ถูกต้อง! การเข้าถึงถูกปฏิเสธโดย ${OWNER_ID}` }], isError: true };
    }

    // 2. ประมวลผลข้อมูล
    const cost = (watts * hours / 1000) * 30 * 4.5;
    const status = cost > 2000 ? "🔴 High Usage" : "🟢 Normal";

    // 3. บันทึกลงฐานข้อมูล
    await db.run(
      "INSERT INTO secure_logs (user_id, label, cost, status) VALUES (?, ?, ?, ?)",
      [user_id, label, cost, status]
    );

    // 4. จำลองการส่ง Line Notify
    const lineMessage = `
📱 [LINE NOTIFY - ${OWNER_ID}]
👤 ผู้ใช้: ${user_id}
🔌 อุปกรณ์: ${label}
💰 ค่าไฟ: ${cost.toFixed(2)} บาท/เดือน
📊 สถานะ: ${status}
---------------------------
(ตรวจสอบข้อมูลสำเร็จโดย ${OWNER_ID})
    `;

    return {
      content: [{ type: "text", text: lineMessage }]
    };
  }
  throw new Error("Tool not found");
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`>>> ${OWNER_ID} Secure Line System Active <<<`);
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function run() {
  const transport = new StdioClientTransport({
    command: "node",
    args: ["--loader", "ts-node/esm", "server.ts"]
  });

  const client = new Client({ name: "user-app", version: "1.0.0" }, { capabilities: {} });
  await client.connect(transport);

  console.log(`--- กำลังส่งข้อมูลผ่านระบบรักษาความปลอดภัย ${"wr-wichit-cominpowerone"} ---`);

  // ทดลองใช้ Key ที่ถูกต้อง
  const successRes = await client.callTool({
    name: "secure_login_and_notify",
    arguments: {
      user_id: "Wichit_User01",
      key: "powerone-1234",
      label: "แอร์ห้องรับแขก",
      watts: 2500,
      hours: 10
    }
  });
  console.log(successRes.content[0].text);

  // ทดลองใช้ Key ที่ "ผิด" (เพื่อทดสอบระบบป้องกัน)
  const failRes = await client.callTool({
    name: "secure_login_and_notify",
    arguments: {
      user_id: "Unknown_User",
      key: "wrong-password",
      label: "พัดลม",
      watts: 50,
      hours: 1
    }
  });
  console.log("ผลการทดสอบรหัสผิด:", failRes.content[0].text);
}

run().catch(console.error);
