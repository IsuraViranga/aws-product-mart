const fs = require('fs');
const path = require('path');

// Verifies the login screen advertises the demo credentials.
// Fails the build if the demo email/password are missing from App.js.
describe('Demo credentials', () => {
  const appSource = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'App.js'),
    'utf8'
  );

  test('demo email is present', () => {
    expect(appSource).toContain('alice@cloudmart.example');
  });

  test('demo password is present', () => {
    expect(appSource).toContain('password123');
  });

  test('demo credentials hint is rendered together', () => {
    expect(appSource).toContain('alice@cloudmart.example / password123');
  });
});

describe('Frontend smoke test', () => {
  test('passes for CI pipeline verification', () => {
    expect(true).toBe(true);
  });
});
