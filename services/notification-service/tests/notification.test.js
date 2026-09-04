const request = require('supertest');

process.env.QUEUE_BACKEND = 'memory';
process.env.EMAIL_BACKEND = 'console';
process.env.ORDER_SERVICE_URL = 'http://localhost:8002';

const app = require('../src/index');

describe('notification-service', () => {
  test('GET /health returns healthy', async () => {
    const res = await request(app).get('/health');

    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('healthy');
  });

  test('GET /ready returns ready', async () => {
    const res = await request(app).get('/ready');

    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ready');
  });

  test('GET /notifications returns notification log', async () => {
    const res = await request(app).get('/notifications');

    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('notifications');
    expect(Array.isArray(res.body.notifications)).toBe(true);
  });
});
