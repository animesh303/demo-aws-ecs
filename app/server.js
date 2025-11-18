const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Demo Web App - AWS ECS Fargate</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
          display: flex;
          justify-content: center;
          align-items: center;
          min-height: 100vh;
          margin: 0;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
        }
        .container {
          text-align: center;
          padding: 2rem;
          background: rgba(255, 255, 255, 0.1);
          border-radius: 10px;
          backdrop-filter: blur(10px);
          box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
        }
        h1 {
          margin: 0 0 1rem 0;
          font-size: 2.5rem;
        }
        p {
          font-size: 1.2rem;
          margin: 0.5rem 0;
        }
        .status {
          margin-top: 2rem;
          padding: 1rem;
          background: rgba(255, 255, 255, 0.2);
          border-radius: 5px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>🚀 Demo Web Application</h1>
        <p>Successfully deployed on AWS ECS Fargate!</p>
        <div class="status">
          <p><strong>Status:</strong> Running</p>
          <p><strong>Port:</strong> ${PORT}</p>
          <p><strong>Time:</strong> ${new Date().toLocaleString()}</p>
        </div>
      </div>
    </body>
    </html>
  `);
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});

