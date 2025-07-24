const express = require('express');
const cors = require('cors');
const axios = require('axios');
const cheerio = require('cheerio');

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.send('Backend is running ✅');
});
app.get('/scrape', async (req, res) => {
  const { url } = req.query;

  if (!url) {
    return res.status(400).json({ error: 'URL query parameter is required' });
  }

  try {
    const response = await axios.get(url);
    const $ = cheerio.load(response.data);
    const price =
      $('#priceblock_ourprice').text().trim() ||
      $('#priceblock_dealprice').text().trim();
    res.json({ price: price || 'Price not found' });
  } catch (error) {
    console.error('Scraping error:', error.message);
    res.status(500).json({ error: error.message });
  }
});
