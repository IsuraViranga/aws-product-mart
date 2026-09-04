const request = require('supertest');

// Force memory backend — no AWS credentials needed in tests
process.env.QUEUE_BACKEND = 'memory';
process.env.PRODUCT_SERVICE_URL = 'http://localhost:8001';

const app = require('../src/index');

describe('order-service', () => {
  test('GET /health returns healthy', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('healthy');
  });

  test('GET /orders returns order list', async () => {
    const res = await request(app).get('/orders');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('orders');
    expect(Array.isArray(res.body.orders)).toBe(true);
  });

  test('GET /orders/:orderId returns 404 for unknown order', async () => {
    const res = await request(app).get('/orders/does-not-exist');
    expect(res.statusCode).toBe(404);
  });

  test('GET /events returns event log', async () => {
    const res = await request(app).get('/events');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('events');
  });

  test('POST /orders returns 400 when body is missing', async () => {
    const res = await request(app)
      .post('/orders')
      .send({});
    expect(res.statusCode).toBe(400);
  });
});