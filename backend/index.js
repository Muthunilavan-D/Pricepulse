const express = require('express');
const cors = require('cors');
const axios = require('axios');
const cheerio = require('cheerio');
const admin = require('firebase-admin');

const app = express();
const PORT = process.env.PORT || 5000;

console.log('Starting server...');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});
const db = admin.firestore();

console.log('Firebase initialized');

app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.send('Backend is running ✅');
});

// Helper function to normalize URL
function normalizeUrl(url) {
  if (!url) return null;
  
  // Remove common tracking parameters but keep the URL mostly intact
  try {
    const urlObj = new URL(url);
    // Remove tracking parameters
    const trackingParams = ['ref', 'tag', 'linkCode', 'creative', 'creativeASIN', 'ie', 'sr', 'keywords', 'qid', 'th', 'psc'];
    
    for (const param of trackingParams) {
      urlObj.searchParams.delete(param);
    }
    
    return urlObj.toString();
  } catch (e) {
    // Return original if URL parsing fails
    return url;
  }
}

// Helper function to scrape product
async function scrapeProduct(url) {
  try {
    // Normalize URL
    const normalizedUrl = normalizeUrl(url);
    console.log('Scraping:', normalizedUrl);

    // Enhanced headers to mimic a real browser
    const headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'none',
      'Cache-Control': 'max-age=0'
    };

    const { data } = await axios.get(normalizedUrl, {
      headers: headers,
      timeout: 20000,
      maxRedirects: 5
    });

    const $ = cheerio.load(data);
    let price = null;
    let title = null;
    let image = null;

    // Check if it's an Amazon URL (including shortened amzn.in)
    const isAmazon = normalizedUrl.includes('amazon.in') || 
                     normalizedUrl.includes('amazon.com') || 
                     normalizedUrl.includes('amzn.in');
    
    if (isAmazon) {
      // Try multiple Amazon price selectors (they change frequently)
      const priceSelectors = [
        '.a-price .a-offscreen',
        '.a-price-whole',
        '#priceblock_ourprice',
        '#priceblock_dealprice',
        '.a-price.a-text-price .a-offscreen',
        '[data-a-color="price"] .a-offscreen',
        '.a-price[data-a-color="price"] .a-offscreen',
        '#price',
        '.apexPriceToPay .a-offscreen',
        '#corePriceDisplay_desktop_feature_div .a-price .a-offscreen'
      ];
      
      for (const selector of priceSelectors) {
        const priceText = $(selector).first().text().trim();
        if (priceText) {
          price = priceText;
          break;
        }
      }

      // Try multiple title selectors
      const titleSelectors = [
        '#productTitle',
        'h1.a-size-large',
        'h1[data-automation-id="title"]',
        '.product-title'
      ];
      
      for (const selector of titleSelectors) {
        const titleText = $(selector).text().trim();
        if (titleText) {
          title = titleText;
          break;
        }
      }

      // Try multiple image selectors
      const imageSelectors = [
        '#landingImage',
        '#imgBlkFront',
        '.a-dynamic-image',
        '#main-image',
        '[data-a-image-name="landingImage"]'
      ];
      
      for (const selector of imageSelectors) {
        const imgSrc = $(selector).attr('src') || $(selector).attr('data-src');
        if (imgSrc) {
          image = imgSrc;
          break;
        }
      }

    } else if (normalizedUrl.includes('flipkart.com')) {
      // Try multiple Flipkart price selectors
      const priceSelectors = [
        'div._30jeq3._16Jk6d',
        '._30jeq3._16Jk6d',
        '._30jeq3',
        '[class*="_30jeq3"]',
        '.dyC4hf ._30jeq3',
        '._25b18c ._30jeq3'
      ];
      
      for (const selector of priceSelectors) {
        const priceText = $(selector).first().text().trim();
        if (priceText) {
          price = priceText;
          break;
        }
      }

      // Try multiple title selectors
      const titleSelectors = [
        'span.B_NuCI',
        '.B_NuCI',
        'h1[class*="B_NuCI"]',
        '.VU-ZEz',
        'h1 span'
      ];
      
      for (const selector of titleSelectors) {
        const titleText = $(selector).text().trim();
        if (titleText) {
          title = titleText;
          break;
        }
      }

      // Try multiple image selectors
      const imageSelectors = [
        'img._396cs4',
        '._396cs4',
        '[class*="_396cs4"]',
        '.CXW8mj img',
        '.q6DClP img'
      ];
      
      for (const selector of imageSelectors) {
        const imgSrc = $(selector).attr('src') || $(selector).attr('data-src');
        if (imgSrc) {
          image = imgSrc;
          break;
        }
      }
    } else {
      console.error('Unsupported URL domain. Only Amazon and Flipkart are supported.');
      return null;
    }

    console.log('Scraping result - Price:', price || 'NOT FOUND', 'Title:', title ? title.substring(0, 50) : 'NOT FOUND');

    if (!price || price.length === 0) {
      console.error('Price not found. Possible reasons:');
      console.error('1. Website structure changed');
      console.error('2. Product page requires login');
      console.error('3. Product is out of stock');
      console.error('4. URL is invalid or not a product page');
      return null;
    }

    return { 
      price: price.trim(), 
      title: (title || 'Unknown Product').trim(), 
      image: (image || '').trim() 
    };
  } catch (error) {
    console.error('Scraping error details:');
    console.error('Error message:', error.message);
    console.error('Error code:', error.code);
    if (error.response) {
      console.error('Response status:', error.response.status);
      console.error('Response headers:', error.response.headers);
    }
    
    // Provide more specific error messages
    if (error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
      console.error('Network error: Could not connect to the website');
    } else if (error.response && error.response.status === 403) {
      console.error('Access denied: Website may be blocking requests');
    } else if (error.response && error.response.status === 404) {
      console.error('Page not found: URL may be invalid');
    }
    
    return null;
  }
}

app.get('/scrape', async (req, res) => {
  const { url } = req.query;
  if (!url) {
    return res.status(400).json({ error: 'URL required' });
  }
  const data = await scrapeProduct(url);
  if (data) {
    res.json(data);
  } else {
    res.status(500).json({ error: 'Failed to scrape' });
  }
});

app.post('/track-product', async (req, res) => {
  const { url } = req.body;
  if (!url) {
    return res.status(400).json({ error: 'URL is required' });
  }

  // Validate URL format
  try {
    const urlObj = new URL(url);
    const hostname = urlObj.hostname.toLowerCase();
    // Accept amazon.in, amazon.com, amzn.in (shortened), and flipkart.com
    const isValidDomain = hostname.includes('amazon') || 
                          hostname.includes('amzn.in') || 
                          hostname.includes('flipkart');
    
    if (!isValidDomain) {
      return res.status(400).json({ 
        error: 'Only Amazon and Flipkart URLs are supported. Please provide a valid product URL.' 
      });
    }
  } catch (e) {
    return res.status(400).json({ error: 'Invalid URL format. Please provide a valid URL.' });
  }

  console.log('Tracking product from URL:', url);
  const data = await scrapeProduct(url);
  
  if (!data || !data.price) {
    return res.status(500).json({ 
      error: 'Could not fetch product details. Possible reasons:\n' +
             '• Website structure may have changed\n' +
             '• Product may require login to view\n' +
             '• Product may be out of stock\n' +
             '• URL may not be a valid product page\n' +
             '• Network connection issue'
    });
  }

  const now = new Date().toISOString();
  const product = {
    url,
    title: data.title,
    price: data.price,
    image: data.image,
    lastChecked: now,
    priceHistory: [{
      price: data.price,
      date: now
    }]
  };

  try {
    await db.collection('products').add(product);
    console.log('Product added successfully:', product.title);
    res.json({ message: 'Product tracked successfully', product });
  } catch (error) {
    console.error('Database error:', error.message);
    res.status(500).json({ error: 'Failed to save product: ' + error.message });
  }
});

app.get('/get-products', async (req, res) => {
  try {
    const snapshot = await db.collection('products').get();
    const products = snapshot.docs.map(doc => {
      const data = doc.data();
      return { 
        id: doc.id, 
        ...data,
        priceHistory: data.priceHistory || []
      };
    });
    res.json(products);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Helper function to update product price with history
async function updateProductPrice(docId, newPrice, currentPriceHistory = []) {
  const now = new Date().toISOString();
  const priceHistory = currentPriceHistory || [];
  
  // Add new price entry if price changed
  const lastPrice = priceHistory.length > 0 ? priceHistory[priceHistory.length - 1].price : null;
  if (lastPrice !== newPrice) {
    priceHistory.push({
      price: newPrice,
      date: now
    });
    
    // Keep only last 30 entries
    if (priceHistory.length > 30) {
      priceHistory.shift();
    }
  }
  
  return db.collection('products').doc(docId).update({
    price: newPrice,
    lastChecked: now,
    priceHistory: priceHistory
  });
}

app.post('/refresh-product', async (req, res) => {
  const { id } = req.body;
  if (!id) {
    return res.status(400).json({ error: 'Product ID is required' });
  }

  try {
    const doc = await db.collection('products').doc(id).get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Product not found' });
    }

    const product = doc.data();
    const newData = await scrapeProduct(product.url);
    
    if (!newData || !newData.price) {
      return res.status(500).json({ error: 'Could not fetch product price' });
    }

    await updateProductPrice(id, newData.price, product.priceHistory || []);
    
    const updatedDoc = await db.collection('products').doc(id).get();
    res.json({ message: 'Product price updated', product: { id: doc.id, ...updatedDoc.data() } });
  } catch (error) {
    console.error('Refresh error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

app.delete('/delete-product', async (req, res) => {
  const { id } = req.query;
  if (!id) {
    return res.status(400).json({ error: 'Product ID is required' });
  }

  try {
    await db.collection('products').doc(id).delete();
    res.json({ message: 'Product deleted successfully' });
  } catch (error) {
    console.error('Delete error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

app.get('/scrape-all', async (req, res) => {
  try {
    const snapshot = await db.collection('products').get();
    const updates = [];

    for (const doc of snapshot.docs) {
      const product = doc.data();
      const newData = await scrapeProduct(product.url);
      if (newData && newData.price) {
        updates.push(updateProductPrice(doc.id, newData.price, product.priceHistory || []));
      }
    }

    await Promise.all(updates);
    res.json({ message: 'All products updated' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('========================================');
  console.log('✓ SERVER IS RUNNING');
  console.log('========================================');
  console.log('Local:   http://localhost:' + PORT);
  console.log('Network: http://192.168.31.248:' + PORT);
  console.log('========================================');
  console.log('Press Ctrl+C to stop');
  console.log('');
});

// Keep process alive
setInterval(() => { }, 1000);
