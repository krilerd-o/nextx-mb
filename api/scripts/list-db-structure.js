/**
 * แสดงโครงสร้างใน DB ที่เชื่อมจาก api/.env
 * - PostgreSQL: รายชื่อตารางใน public schema
 * - MongoDB: รายชื่อ collections
 * รัน: node scripts/list-db-structure.js (จากโฟลเดอร์ api)
 */
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const { Pool } = require('pg');
const { MongoClient } = require('mongodb');

const pgConfig = {
  host: process.env.PG_HOST || process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.PG_PORT || process.env.DB_PORT || '5432', 10),
  database: process.env.PG_DATABASE || process.env.DB_NAME || 'db_moai_next',
  user: process.env.PG_USER || process.env.DB_USER || 'postgres',
  password: process.env.PG_PASSWORD || process.env.DB_PASSWORD || 'postgres',
};

async function listPg() {
  const pool = new Pool(pgConfig);
  try {
    const r = await pool.query(`
      SELECT table_schema, table_name
      FROM information_schema.tables
      WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
      ORDER BY table_schema, table_name
    `);
    return r.rows;
  } finally {
    await pool.end();
  }
}

async function listMongo() {
  const uri = process.env.MONGODB_URI || process.env.MONGO_URI || 'mongodb://localhost:27017';
  const dbName = process.env.MONGODB_DB_NAME || process.env.MONGO_DB || 'nextx';
  const client = new MongoClient(uri);
  try {
    await client.connect();
    const db = client.db(dbName);
    const cols = await db.listCollections().toArray();
    return cols.map((c) => c.name);
  } finally {
    await client.close();
  }
}

async function main() {
  console.log(
    'Database: ',
    pgConfig.database,
    '(PostgreSQL)',
    process.env.MONGODB_DB_NAME || process.env.MONGO_DB || 'nextx',
    '(MongoDB)\n',
  );

  try {
    const tables = await listPg();
    console.log('--- PostgreSQL (ตาราง) ---');
    if (tables.length === 0) console.log('  (ไม่มีตารางใน schema ที่ไม่ใช่ system)');
    else tables.forEach((t) => console.log('  ', t.table_schema + '.' + t.table_name));
  } catch (e) {
    console.log('PostgreSQL:', e.message);
  }

  console.log('');
  try {
    const cols = await listMongo();
    console.log('--- MongoDB (collections) ---');
    if (cols.length === 0) console.log('  (ไม่มี collection)');
    else cols.forEach((c) => console.log('  ', c));
  } catch (e) {
    console.log('MongoDB:', e.message);
  }

  console.log('\nDone.');
}

main();
