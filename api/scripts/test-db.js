/**
 * ทดสอบการเชื่อมต่อ PostgreSQL และ MongoDB ตาม api/.env
 * รัน: node scripts/test-db.js (จากโฟลเดอร์ api)
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

async function test() {
  console.log('Testing DB connection (api/.env)...\n');

  // PostgreSQL
  const pool = new Pool(pgConfig);
  try {
    await pool.query('SELECT 1');
    console.log('PostgreSQL: OK');
  } catch (e) {
    console.log('PostgreSQL: FAIL -', e.message);
    if (e.code === '3D000') console.log('  -> สร้าง database ก่อน: CREATE DATABASE ' + (pgConfig.database) + ';');
  } finally {
    await pool.end();
  }

  // MongoDB
  const mongoUri = process.env.MONGODB_URI || process.env.MONGO_URI || 'mongodb://localhost:27017';
  const client = new MongoClient(mongoUri);
  try {
    await client.connect();
    await client.db(process.env.MONGODB_DB_NAME || process.env.MONGO_DB || 'nextx').command({ ping: 1 });
    console.log('MongoDB: OK');
  } catch (e) {
    console.log('MongoDB: FAIL -', e.message);
  } finally {
    await client.close();
  }

  console.log('\nDone. แก้ api/.env ให้ตรงกับโปรเจค Web แล้วรัน run-api.cmd ใหม่');
}

test();
