const express = require('express');
const cors = require('cors');
const axios = require('axios');
const cheerio = require('cheerio');
const admin = require('firebase-admin');

const app = express();
const PORT = process.env.PORT || 5000;

console.log('Starting server...');

// Initialize Firebase Admin
let serviceAccount;
if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  // Use environment variable (for production/deployment)
  try {
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    console.log('✅ Using Firebase service account from environment variable');
  } catch (e) {
    console.error('❌ Error parsing FIREBASE_SERVICE_ACCOUNT:', e.message);
    throw new Error('Invalid FIREBASE_SERVICE_ACCOUNT environment variable');
  }
} else {
  // Use local file (for development)
  try {
    serviceAccount = require('./serviceAccountKey.json');
    console.log('✅ Using Firebase service account from local file');
  } catch (e) {
    console.error('❌ Error loading serviceAccountKey.json:', e.message);
    throw new Error('Firebase service account not found. Set FIREBASE_SERVICE_ACCOUNT environment variable or provide serviceAccountKey.json file');
  }
}

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

// Test endpoint to verify delete route is accessible
app.get('/test-delete', (req, res) => {
  res.json({ message: 'Delete endpoint is accessible', method: 'GET' });
});

app.post('/test-delete', (req, res) => {
  res.json({ 
    message: 'Delete endpoint is accessible', 
    method: 'POST',
    body: req.body 
  });
});

// Test endpoint to debug URL resolution
app.get('/test-url', async (req, res) => {
  const { url } = req.query;
  if (!url) {
    return res.status(400).json({ error: 'URL parameter required' });
  }
  
  try {
    console.log(`\n🧪 Testing URL resolution for: ${url}`);
    const resolved = await resolveShortUrl(url);
    const normalized = normalizeUrl(resolved);
    
    res.json({
      original: url,
      resolved: resolved,
      normalized: normalized,
      isResolved: resolved !== url,
      isNormalized: normalized !== resolved
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Helper function to resolve shortened URLs (amzn.in, amzn.to, dl.flipkart.com)
async function resolveShortUrl(url) {
  try {
    const urlObj = new URL(url);
    const hostname = urlObj.hostname.toLowerCase();
    
    // Check if it's a shortened URL (Amazon or Flipkart)
    const isShortenedAmazon = hostname === 'amzn.in' || hostname === 'amzn.to' || hostname.includes('amzn.');
    const isShortenedFlipkart = hostname === 'dl.flipkart.com' || hostname.includes('dl.flipkart');
    
    if (isShortenedAmazon || isShortenedFlipkart) {
      const urlType = isShortenedAmazon ? 'Amazon' : 'Flipkart';
      console.log(`🔗 Detected shortened ${urlType} URL: ${url}`);
      
      try {
        // First, try HEAD request to get redirect location without downloading content
        try {
          const headResponse = await axios.head(url, {
            maxRedirects: 0,
            timeout: 10000,
            validateStatus: (status) => status >= 200 && status < 500,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            }
          });
          
          // Check for location header
          if (headResponse.headers.location) {
            let resolvedUrl = headResponse.headers.location;
            if (!resolvedUrl.startsWith('http')) {
              resolvedUrl = isShortenedAmazon 
                ? `https://www.amazon.in${resolvedUrl}` 
                : `https://www.flipkart.com${resolvedUrl}`;
            }
            console.log(`✅ Resolved from HEAD location header: ${url} -> ${resolvedUrl}`);
            return resolvedUrl;
          }
        } catch (headError) {
          // If HEAD fails, check if it's a redirect
          if (headError.response && headError.response.status >= 300 && headError.response.status < 400) {
            const location = headError.response.headers.location;
            if (location) {
              let resolvedUrl = location;
              if (!location.startsWith('http')) {
                resolvedUrl = isShortenedAmazon 
                  ? `https://www.amazon.in${location}` 
                  : `https://www.flipkart.com${location}`;
              }
              console.log(`✅ Resolved from HEAD redirect: ${url} -> ${resolvedUrl}`);
              return resolvedUrl;
            }
          }
          console.log(`⚠️ HEAD request failed, trying GET: ${headError.message}`);
        }
        
        // If HEAD didn't work, use GET request with maxRedirects to follow redirects
        const response = await axios.get(url, {
          maxRedirects: 10,
          timeout: 20000,
          validateStatus: (status) => status >= 200 && status < 500,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
          }
        });
        
        // Get the final URL after all redirects - try multiple methods
        let finalUrl = null;
        
        // Method 1: Check response.request.res.responseUrl (Node.js)
        if (response.request?.res?.responseUrl) {
          finalUrl = response.request.res.responseUrl;
        }
        // Method 2: Check response.request.responseURL (browser-like)
        else if (response.request?.responseURL) {
          finalUrl = response.request.responseURL;
        }
        // Method 3: Check response.config.url (axios config)
        else if (response.config?.url) {
          finalUrl = response.config.url;
        }
        // Method 4: Check if current URL is different from original
        else if (response.request?.path) {
          const currentHost = response.request.host || response.request.getHeader('host');
          if (currentHost && currentHost !== hostname) {
            finalUrl = `https://${currentHost}${response.request.path}`;
          }
        }
        
        // If we got a different URL, verify it's valid
        if (finalUrl && finalUrl !== url) {
          const isValidAmazon = isShortenedAmazon && (finalUrl.includes('amazon.in') || finalUrl.includes('amazon.com'));
          const isValidFlipkart = isShortenedFlipkart && finalUrl.includes('flipkart.com');
          
          if (isValidAmazon || isValidFlipkart) {
            console.log(`✅ Resolved shortened ${urlType} URL via GET: ${url} -> ${finalUrl}`);
            return finalUrl;
          } else {
            console.log(`⚠️ Resolved URL doesn't match expected domain: ${finalUrl}`);
          }
        }
        
        // If we still don't have a valid URL, try to extract from response data
        if (!finalUrl || finalUrl === url) {
          const $ = cheerio.load(response.data);
          // Look for meta refresh or canonical link
          const canonical = $('link[rel="canonical"]').attr('href');
          if (canonical) {
            console.log(`✅ Found canonical URL: ${canonical}`);
            return canonical;
          }
          
          // Try to find redirect in meta tag
          const metaRefresh = $('meta[http-equiv="refresh"]').attr('content');
          if (metaRefresh) {
            const urlMatch = metaRefresh.match(/url=(.+)/i);
            if (urlMatch && urlMatch[1]) {
              let redirectUrl = urlMatch[1].trim();
              if (!redirectUrl.startsWith('http')) {
                redirectUrl = isShortenedAmazon 
                  ? `https://www.amazon.in${redirectUrl}` 
                  : `https://www.flipkart.com${redirectUrl}`;
              }
              console.log(`✅ Found redirect URL from meta refresh: ${redirectUrl}`);
              return redirectUrl;
            }
          }
        }
        
        // If URL resolution failed but we got a response, try using the response URL
        if (response.request && response.request.res && response.request.res.responseUrl) {
          const responseUrl = response.request.res.responseUrl;
          if (responseUrl && responseUrl !== url && (responseUrl.includes('amazon') || responseUrl.includes('flipkart'))) {
            console.log(`✅ Using response URL: ${responseUrl}`);
            return responseUrl;
          }
        }
        
        console.log(`⚠️ Could not resolve shortened URL, using original: ${url}`);
      } catch (error) {
        console.error(`❌ Error resolving short ${urlType} URL:`, error.message);
        if (error.response) {
          console.error(`   Status: ${error.response.status}`);
          console.error(`   Headers:`, error.response.headers);
        }
      }
    }
    
    return url;
  } catch (e) {
    console.error('Error in resolveShortUrl:', e.message);
    return url; // Return original if resolution fails
  }
}

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

// Helper function to get random user agent (rotates to avoid detection)
function getRandomUserAgent() {
  const userAgents = [
    // Desktop Chrome (latest)
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    // Desktop Chrome (slightly older)
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    // Desktop Firefox
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0',
    // Mobile Chrome (Android)
    'Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
    // Mobile Safari (iOS)
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    // Desktop Edge
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0'
  ];
  return userAgents[Math.floor(Math.random() * userAgents.length)];
}

// Helper function to add random delay (evades rate limiting)
function randomDelay(min = 1000, max = 3000) {
  const delay = Math.floor(Math.random() * (max - min + 1)) + min;
  return new Promise(resolve => setTimeout(resolve, delay));
}

// Helper function to scrape product
const MAX_RETRIES = 2;
async function scrapeProduct(url, retryCount = 0) {
  try {
    console.log(`\n🔍 Starting scrape for URL: ${url}${retryCount > 0 ? ` (Retry ${retryCount}/${MAX_RETRIES})` : ''}`);
    
    // Add random delay before request (helps evade rate limiting)
    if (retryCount === 0) {
      await randomDelay(1500, 2500);
    }
    
    // First, resolve shortened URLs (like dl.flipkart.com)
    const resolvedUrl = await resolveShortUrl(url);
    console.log(`📎 Resolved URL: ${resolvedUrl}`);
    
    // Then normalize URL
    let normalizedUrl = normalizeUrl(resolvedUrl);
    console.log(`🔧 Normalized URL: ${normalizedUrl}`);
    
    // Strategy: Try mobile version first for Amazon (less likely to show CAPTCHA)
    // If that fails, retry with desktop version
    const isAmazonUrl = normalizedUrl.includes('amazon.in') || normalizedUrl.includes('amazon.com');
    if (isAmazonUrl) {
      // First attempt: try mobile version (less bot detection)
      if (retryCount === 0 && !normalizedUrl.includes('m.amazon')) {
        normalizedUrl = normalizedUrl.replace(/www\.amazon\.(in|com)/, 'm.amazon.$1');
        console.log(`📱 Using mobile version first (less bot detection): ${normalizedUrl}`);
      }
      // Second attempt: try desktop version if mobile failed
      else if (retryCount === 1 && normalizedUrl.includes('m.amazon')) {
        normalizedUrl = normalizedUrl.replace(/m\.amazon\.(in|com)/, 'www.amazon.$1');
        console.log(`🖥️  Retrying with desktop version: ${normalizedUrl}`);
      }
    }
    
    console.log(`🌐 Final URL to scrape: ${normalizedUrl}`);

    // Rotate user agent for each request
    const userAgent = getRandomUserAgent();
    console.log(`🔄 Using User-Agent: ${userAgent.substring(0, 50)}...`);

    // Enhanced headers to mimic a real browser (more realistic)
    // Use mobile headers if using mobile URL
    const isMobileUrl = normalizedUrl.includes('m.amazon');
    const headers = {
      'User-Agent': userAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Accept-Language': isMobileUrl ? 'en-IN,en;q=0.9' : 'en-IN,en-US;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': isMobileUrl ? 'none' : 'none',
      'Sec-Fetch-User': '?1',
      'Cache-Control': 'max-age=0',
      'Referer': 'https://www.google.com/',
      'DNT': '1',
      'sec-ch-ua': isMobileUrl ? '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"' : '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
      'sec-ch-ua-mobile': isMobileUrl ? '?1' : '?0',
      'sec-ch-ua-platform': isMobileUrl ? '"Android"' : '"Windows"'
    };

    let response;
    try {
      response = await axios.get(normalizedUrl, {
        headers: headers,
        timeout: 20000,
        maxRedirects: 5,
        validateStatus: (status) => status >= 200 && status < 500
      });
    } catch (requestError) {
      console.error('❌ Request failed:', requestError.message);
      if (requestError.response) {
        console.error('   Status:', requestError.response.status);
        console.error('   Status text:', requestError.response.statusText);
      }
      throw requestError;
    }

    // Check if we got redirected to a different URL
    const finalRequestUrl = response.request?.res?.responseURL || response.request?.responseURL || normalizedUrl;
    if (finalRequestUrl !== normalizedUrl) {
      console.log(`📎 Request was redirected to: ${finalRequestUrl}`);
    }

    const $ = cheerio.load(response.data);
    
    // Enhanced CAPTCHA detection - check for multiple indicators
    const pageHtml = $.html().toLowerCase();
    const pageText = $.text().toLowerCase();
    const responseText = response.data.toString().toLowerCase();
    
    const captchaIndicators = [
      'captcha',
      'robot',
      'sorry, we just need to make sure',
      'enter the characters you see',
      'click the button',
      'opfcaptcha',
      'amazon captcha',
      'try a different image',
      'automated access',
      'unusual traffic',
      'verify you are human'
    ];
    
    const isBlocked = captchaIndicators.some(indicator => 
      pageHtml.includes(indicator) || 
      pageText.includes(indicator) ||
      responseText.includes(indicator)
    );
    
    // Check for specific Amazon CAPTCHA elements
    const hasCaptchaElement = $('#captchacharacters').length > 0 || 
                             $('[id*="captcha"]').length > 0 ||
                             $('[class*="captcha"]').length > 0 ||
                             pageHtml.includes('opfcaptcha.amazon.in');
    
    if (isBlocked || hasCaptchaElement) {
      console.warn('⚠️  Page appears to be blocked or requires CAPTCHA');
      
      // If it's Amazon and we haven't tried mobile yet, retry with mobile
      if (isAmazonUrl && retryCount === 0 && !normalizedUrl.includes('m.amazon')) {
        console.log('🔄 CAPTCHA detected, will retry with mobile version...');
        // Will retry below
      } else if (retryCount < MAX_RETRIES) {
        // Try one more time with different approach
        console.log('🔄 Retrying after CAPTCHA detection...');
      } else {
        // Final attempt - try to extract anyway in case CAPTCHA is just a warning
        console.warn('⚠️  CAPTCHA detected but attempting to extract data anyway...');
      }
    }
    let price = null;
    let title = null;
    let image = null;

    // Check if it's an Amazon URL (all variations)
    // Supports: amazon.in, amazon.com, amzn.in, amzn.to, m.amazon.in, m.amazon.com
    const isAmazon = /(?:amazon\.(?:in|com)|amzn\.(?:in|to)|m\.amazon\.(?:in|com))/.test(normalizedUrl);
    
    // Check if it's a Flipkart URL (all variations)
    // Supports: flipkart.com, www.flipkart.com, dl.flipkart.com, m.flipkart.com
    const isFlipkart = /(?:flipkart\.com|dl\.flipkart\.com|m\.flipkart\.com)/.test(normalizedUrl);
    
    if (isAmazon) {
      console.log('🛒 Scraping Amazon product...');
      
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
        '#corePriceDisplay_desktop_feature_div .a-price .a-offscreen',
        '.a-price-symbol + .a-price-whole',
        'span.a-price-whole',
        '.a-price .a-price-whole',
        '#priceblock_saleprice',
        '#priceblock_buyingprice',
        '.a-size-medium.a-color-price',
        '[id*="price"]',
        '[class*="price"]',
        '.a-text-price .a-offscreen',
        'span[data-a-color="price"]'
      ];
      
      console.log(`   Trying ${priceSelectors.length} price selectors...`);
      for (const selector of priceSelectors) {
        const priceText = $(selector).first().text().trim();
        if (priceText) {
          price = priceText;
          console.log(`✅ Found Amazon price with selector: ${selector} = ${priceText}`);
          break;
        }
      }

      // If all selectors fail, try extracting from JSON-LD structured data
      if (!price) {
        console.log('   All price selectors failed. Trying JSON-LD structured data...');
        try {
          const jsonLdScripts = $('script[type="application/ld+json"]');
          for (let i = 0; i < jsonLdScripts.length; i++) {
            try {
              const jsonData = JSON.parse($(jsonLdScripts[i]).html());
              if (jsonData.offers && jsonData.offers.price) {
                const extractedPrice = jsonData.offers.price;
                if (typeof extractedPrice === 'number') {
                  price = `₹${extractedPrice.toLocaleString('en-IN')}`;
                  console.log(`✅ Found price in JSON-LD: ${price}`);
                  break;
                } else if (typeof extractedPrice === 'string') {
                  price = extractedPrice;
                  console.log(`✅ Found price in JSON-LD: ${price}`);
                  break;
                }
              }
              // Also check for aggregateOffer
              if (jsonData.aggregateOffer && jsonData.aggregateOffer.lowPrice) {
                const extractedPrice = jsonData.aggregateOffer.lowPrice;
                if (typeof extractedPrice === 'number') {
                  price = `₹${extractedPrice.toLocaleString('en-IN')}`;
                  console.log(`✅ Found price in JSON-LD aggregateOffer: ${price}`);
                  break;
                }
              }
            } catch (parseError) {
              // Continue to next script tag
              continue;
            }
          }
        } catch (jsonError) {
          console.log(`   JSON-LD extraction failed: ${jsonError.message}`);
        }
      }

      // Fallback: Try extracting from embedded JavaScript data
      if (!price) {
        console.log('   Trying JavaScript data extraction...');
        try {
          // Look for Amazon's price data in script tags
          const scripts = $('script');
          for (let i = 0; i < scripts.length; i++) {
            const scriptContent = $(scripts[i]).html();
            if (scriptContent) {
              // Try to find price in various JavaScript patterns
              // Pattern 1: "price":1234.56 or "price":"₹1,234"
              const pricePattern1 = /["']price["']\s*:\s*["']?([₹]?[\d,]+(?:\.\d{2})?)/i;
              const match1 = scriptContent.match(pricePattern1);
              if (match1 && match1[1]) {
                price = match1[1].includes('₹') ? match1[1] : `₹${match1[1]}`;
                console.log(`✅ Found price in JavaScript (pattern 1): ${price}`);
                break;
              }
              
              // Pattern 2: "displayPrice":"₹1,234"
              const pricePattern2 = /["']displayPrice["']\s*:\s*["']([₹][\d,]+(?:\.\d{2})?)/i;
              const match2 = scriptContent.match(pricePattern2);
              if (match2 && match2[1]) {
                price = match2[1];
                console.log(`✅ Found price in JavaScript (pattern 2): ${price}`);
                break;
              }
              
              // Pattern 3: "amount":1234.56
              const pricePattern3 = /["']amount["']\s*:\s*["']?([\d,]+(?:\.\d{2})?)/i;
              const match3 = scriptContent.match(pricePattern3);
              if (match3 && match3[1]) {
                price = `₹${match3[1]}`;
                console.log(`✅ Found price in JavaScript (pattern 3): ${price}`);
                break;
              }
            }
          }
        } catch (jsError) {
          console.log(`   JavaScript extraction failed: ${jsError.message}`);
        }
      }

      // Fallback: Try regex pattern matching for price
      if (!price) {
        console.log('   Trying regex fallback for price...');
        const allText = $.text();
        // Match Indian Rupee prices: ₹1,234 or ₹1234 or Rs. 1,234
        const priceRegex = /(?:₹|Rs\.?)\s*[\d,]+(?:\.\d{2})?/g;
        const matches = allText.match(priceRegex);
        if (matches && matches.length > 0) {
          // Get the first substantial price (usually the main price)
          price = matches[0].trim();
          console.log(`✅ Found price using regex fallback: ${price}`);
        }
      }

      // Try multiple title selectors
      const titleSelectors = [
        '#productTitle',
        'h1.a-size-large',
        'h1[data-automation-id="title"]',
        '.product-title',
        'h1 span',
        '#title',
        'h1.a-size-base-plus',
        'span#productTitle'
      ];
      
      console.log(`   Trying ${titleSelectors.length} title selectors...`);
      for (const selector of titleSelectors) {
        const titleText = $(selector).text().trim();
        if (titleText) {
          title = titleText;
          console.log(`✅ Found Amazon title with selector: ${selector}`);
          break;
        }
      }

      // Fallback: Try JSON-LD for title
      if (!title) {
        console.log('   Trying JSON-LD for title...');
        try {
          const jsonLdScripts = $('script[type="application/ld+json"]');
          for (let i = 0; i < jsonLdScripts.length; i++) {
            try {
              const jsonData = JSON.parse($(jsonLdScripts[i]).html());
              if (jsonData.name) {
                title = jsonData.name;
                console.log(`✅ Found title in JSON-LD: ${title.substring(0, 50)}...`);
                break;
              }
            } catch (parseError) {
              continue;
            }
          }
        } catch (jsonError) {
          console.log(`   JSON-LD title extraction failed: ${jsonError.message}`);
        }
      }

      // Try multiple image selectors
      const imageSelectors = [
        '#landingImage',
        '#imgBlkFront',
        '.a-dynamic-image',
        '#main-image',
        '[data-a-image-name="landingImage"]',
        '#imgTagWrapperId img',
        '#main-image-container img',
        '.a-button-selected img',
        'img[data-old-hires]',
        'img[data-a-dynamic-image]'
      ];
      
      console.log(`   Trying ${imageSelectors.length} image selectors...`);
      for (const selector of imageSelectors) {
        const imgSrc = $(selector).attr('src') || $(selector).attr('data-src') || $(selector).attr('data-old-hires') || $(selector).attr('data-a-dynamic-image');
        if (imgSrc) {
          // Handle data-a-dynamic-image which is a JSON object
          if (imgSrc.startsWith('{')) {
            try {
              const imgData = JSON.parse(imgSrc);
              const firstKey = Object.keys(imgData)[0];
              if (firstKey) {
                image = firstKey;
                console.log(`✅ Found Amazon image with selector: ${selector}`);
                break;
              }
            } catch (e) {
              continue;
            }
          } else {
            image = imgSrc;
            console.log(`✅ Found Amazon image with selector: ${selector}`);
            break;
          }
        }
      }

      // Fallback: Try JSON-LD for image
      if (!image) {
        console.log('   Trying JSON-LD for image...');
        try {
          const jsonLdScripts = $('script[type="application/ld+json"]');
          for (let i = 0; i < jsonLdScripts.length; i++) {
            try {
              const jsonData = JSON.parse($(jsonLdScripts[i]).html());
              if (jsonData.image) {
                if (Array.isArray(jsonData.image)) {
                  image = jsonData.image[0];
                } else if (typeof jsonData.image === 'string') {
                  image = jsonData.image;
                } else if (jsonData.image.url) {
                  image = jsonData.image.url;
                }
                if (image) {
                  console.log(`✅ Found image in JSON-LD`);
                  break;
                }
              }
            } catch (parseError) {
              continue;
            }
          }
        } catch (jsonError) {
          console.log(`   JSON-LD image extraction failed: ${jsonError.message}`);
        }
      }

    } else if (isFlipkart) {
      console.log('🛒 Scraping Flipkart product...');
      // Try multiple Flipkart price selectors (updated for current Flipkart structure)
      const priceSelectors = [
        'div._30jeq3._16Jk6d',      // Main price selector
        '._30jeq3._16Jk6d',         // Alternative
        '._30jeq3',                  // Fallback
        '[class*="_30jeq3"]',       // Partial match
        '.dyC4hf ._30jeq3',         // Container variant
        '._25b18c ._30jeq3',        // Another container
        'div[class*="Nx9bqj"]',     // Newer Flipkart selector
        '._1vC4OE._2rQ-NK',        // Alternative price class
        'span[class*="price"]',     // Generic price span
        '.a-price-whole',           // Sometimes Flipkart uses similar classes
        '[data-id="price"]',        // Data attribute selector
        'span[class*="_16Jk6d"]'    // Price container class
      ];
      
      for (const selector of priceSelectors) {
        const priceText = $(selector).first().text().trim();
        if (priceText) {
          price = priceText;
          console.log(`✅ Found Flipkart price with selector: ${selector} = ${priceText}`);
          break;
        }
      }
      
      // If all selectors fail, try regex fallback
      if (!price) {
        console.error('❌ All Flipkart price selectors failed. Trying regex fallback...');
        const allText = $.text();
        const priceRegex = /₹[\s]*[\d,]+/g;
        const matches = allText.match(priceRegex);
        if (matches && matches.length > 0) {
          // Get the first substantial price (usually the main price)
          price = matches[0].trim();
          console.log(`✅ Found price using regex fallback: ${price}`);
        }
      }

      // Try multiple title selectors (updated for current Flipkart structure)
      const titleSelectors = [
        'span.B_NuCI',           // Main title selector
        '.B_NuCI',                // Alternative
        'h1[class*="B_NuCI"]',   // H1 variant
        '.VU-ZEz',                // Alternative class
        'h1 span',                // Generic h1 span
        'h1.yhB1nd',              // Newer selector
        'span[class*="B_NuCI"]',  // Partial match
        'h1[data-id]',            // Data attribute variant
        '.product-title',         // Generic product title
        'h1'                      // Fallback to any h1
      ];
      
      console.log('📝 Searching for Flipkart title...');
      for (const selector of titleSelectors) {
        const titleText = $(selector).text().trim();
        if (titleText) {
          title = titleText;
          console.log(`✅ Found Flipkart title with selector: ${selector}`);
          break;
        }
      }

      if (!title) {
        console.error('⚠️  WARNING: Flipkart title not found!');
      } else {
        console.log(`✅ Title found: ${title.substring(0, 50)}...`);
      }

      console.log('\n🖼️  ========== STARTING FLIPKART IMAGE DETECTION ==========');
      console.log('🖼️  Searching for Flipkart product image...');
      console.log('   DEBUG: About to start image detection...');
      console.log('   Starting image detection...');
      console.log('   Current image value before detection:', image || 'null/undefined');
      
      // Method 1: Try specific Flipkart image selectors
      const imageSelectors = [
        'img._396cs4',                    // Main image selector
        'img[class*="_396cs4"]',          // Class contains _396cs4
        '._396cs4',                       // Direct class
        '.CXW8mj img',                    // Container variant
        'div.CXW8mj img',                 // Container div
        '.q6DClP img',                    // Another container
        'div.q6DClP img',                 // Container div variant
        'img[class*="_2r_T1I"]',          // Newer image class
        'img._2r_T1I',                    // Direct class match
        'div[class*="CXW8mj"] img',       // Container div with img
        'div[class*="q6DClP"] img',       // Container div variant
        'img[data-src]',                  // Lazy-loaded images
        'img[data-lazy-src]',             // Lazy-loaded variant
        'img[data-original]',             // Original image
        'img[src*="rukminim"]',           // Flipkart CDN
        'img[src*="img.flipkart"]',       // Flipkart image CDN
        'img[src*="flipkart"]',           // Any Flipkart URL
        '.product-image img',              // Generic product image
        '#product-image img',              // ID-based selector
        'img[alt*="product"]',            // Image with product alt
        'img[data-id]',                   // Image with data-id
      ];
      
      console.log(`   Trying ${imageSelectors.length} image selectors...`);
      for (const selector of imageSelectors) {
        try {
          const imgElements = $(selector);
          if (imgElements.length > 0) {
            console.log(`   Checking selector "${selector}": found ${imgElements.length} elements`);
            // Try all matching images, not just first
            for (let i = 0; i < Math.min(imgElements.length, 5); i++) {
              const imgElement = $(imgElements[i]);
              
              // Try multiple attributes for image source
              const srcAttr = imgElement.attr('src');
              const dataSrcAttr = imgElement.attr('data-src');
              const dataLazySrcAttr = imgElement.attr('data-lazy-src');
              const dataOriginalAttr = imgElement.attr('data-original');
              const srcsetAttr = imgElement.attr('srcset');
              
              let imgSrc = srcAttr || dataSrcAttr || dataLazySrcAttr || dataOriginalAttr || (srcsetAttr ? srcsetAttr.split(' ')[0] : null);
              
              console.log(`   [${selector}][${i}] Image attributes: src="${srcAttr ? srcAttr.substring(0, 50) : 'null'}", data-src="${dataSrcAttr ? dataSrcAttr.substring(0, 50) : 'null'}", data-lazy-src="${dataLazySrcAttr ? dataLazySrcAttr.substring(0, 50) : 'null'}"`);
              
              if (imgSrc) {
                console.log(`   [${selector}][${i}] Found imgSrc: ${imgSrc.substring(0, 100)}...`);
                
                // Clean up the URL
                imgSrc = imgSrc.trim();
                
                // Remove query parameters that might cause issues
                if (imgSrc.includes('?')) {
                  imgSrc = imgSrc.split('?')[0];
                }
                
                // If src is relative, make it absolute
                if (!imgSrc.startsWith('http')) {
                  if (imgSrc.startsWith('//')) {
                    imgSrc = 'https:' + imgSrc;
                  } else if (imgSrc.startsWith('/')) {
                    imgSrc = 'https://www.flipkart.com' + imgSrc;
                  }
                }
                
                // Validate it's a real image URL (relaxed for Flipkart)
                if (imgSrc && imgSrc.length > 10) {
                  // Check if it's NOT a placeholder or invalid image
                  const isInvalid = imgSrc.includes('placeholder') || 
                                  imgSrc.includes('data:image') ||
                                  imgSrc.includes('logo') ||
                                  imgSrc.includes('icon') ||
                                  imgSrc.includes('banner') ||
                                  imgSrc.includes('sprite');
                  
                  // Check if it looks like a valid image URL
                  const looksValid = imgSrc.includes('.jpg') || 
                                   imgSrc.includes('.jpeg') || 
                                   imgSrc.includes('.png') || 
                                   imgSrc.includes('.webp') ||
                                   imgSrc.includes('rukminim') ||
                                   imgSrc.includes('img.flipkart') ||
                                   imgSrc.includes('flipkart.com') ||
                                   (imgSrc.startsWith('http') && imgSrc.length > 30);
                  
                  console.log(`   [${selector}][${i}] Validation: length=${imgSrc.length}, isInvalid=${isInvalid}, looksValid=${looksValid}`);
                  
                  if (!isInvalid && looksValid) {
                    image = imgSrc;
                    console.log(`✅✅✅ Found Flipkart image with selector: ${selector} (index ${i})`);
                    console.log(`   Image URL: ${imgSrc.substring(0, 120)}...`);
                    break;
                  } else {
                    console.log(`   ⚠️ Rejected image URL (invalid=${isInvalid}, valid=${looksValid}): ${imgSrc.substring(0, 80)}...`);
                  }
                } else {
                  console.log(`   ⚠️ Image URL too short: length=${imgSrc ? imgSrc.length : 0}`);
                }
              } else {
                console.log(`   [${selector}][${i}] No image source found in any attribute`);
              }
            }
            if (image) break;
          }
        } catch (e) {
          // Continue to next selector
        }
      }
      
      // Method 2: If still no image, try to find any image in the product area
      if (!image) {
        console.log('⚠️  Standard selectors failed, trying container search...');
        // Look for images in common product containers
        const productContainers = [
          'div[class*="CXW8mj"]',
          'div[class*="q6DClP"]',
          'div[class*="_2r_T1I"]',
          'div[class*="_396cs4"]',
          'div[class*="product"]',
          'div[class*="image"]',
          'div[class*="Image"]',
          '.product-image-container',
          '#product-image-container',
          '[class*="product-image"]'
        ];
        
        for (const containerSelector of productContainers) {
          const containers = $(containerSelector);
          for (let i = 0; i < Math.min(containers.length, 3); i++) {
            const container = $(containers[i]);
            const imgs = container.find('img');
            
            for (let j = 0; j < Math.min(imgs.length, 5); j++) {
              const img = $(imgs[j]);
              let imgSrc = img.attr('src') || 
                          img.attr('data-src') || 
                          img.attr('data-lazy-src') ||
                          img.attr('data-original') ||
                          img.attr('srcset')?.split(' ')[0];
              
              if (imgSrc) {
                imgSrc = imgSrc.trim();
                if (imgSrc.includes('?')) imgSrc = imgSrc.split('?')[0];
                
                if (!imgSrc.startsWith('http')) {
                  if (imgSrc.startsWith('//')) {
                    imgSrc = 'https:' + imgSrc;
                  } else if (imgSrc.startsWith('/')) {
                    imgSrc = 'https://www.flipkart.com' + imgSrc;
                  }
                }
                
                if (imgSrc && imgSrc.length > 10) {
                  const isInvalid = imgSrc.includes('placeholder') || 
                                  imgSrc.includes('data:image') ||
                                  imgSrc.includes('logo') ||
                                  imgSrc.includes('icon') ||
                                  imgSrc.includes('banner') ||
                                  imgSrc.includes('sprite');
                  
                  const looksValid = imgSrc.includes('.jpg') || 
                                   imgSrc.includes('.jpeg') || 
                                   imgSrc.includes('.png') || 
                                   imgSrc.includes('.webp') || 
                                   imgSrc.includes('rukminim') || 
                                   imgSrc.includes('img.flipkart') || 
                                   imgSrc.includes('flipkart.com') ||
                                   (imgSrc.startsWith('http') && imgSrc.length > 30);
                  
                  if (!isInvalid && looksValid) {
                    image = imgSrc;
                    console.log(`✅ Found image in container: ${containerSelector} (img ${j})`);
                    console.log(`   Image URL: ${imgSrc.substring(0, 120)}...`);
                    break;
                  }
                }
              }
            }
            if (image) break;
          }
          if (image) break;
        }
      }
      
      // Method 3: Last resort - scan ALL images on the page
      if (!image) {
        console.log('⚠️  Container methods failed, scanning all images on page...');
        const allImages = $('img');
        console.log(`   Found ${allImages.length} total images on page`);
        
        for (let i = 0; i < Math.min(allImages.length, 20); i++) {
          const $img = $(allImages[i]);
          let imgSrc = $img.attr('src') || 
                      $img.attr('data-src') || 
                      $img.attr('data-lazy-src') ||
                      $img.attr('data-original') ||
                      $img.attr('srcset')?.split(' ')[0];
          
          if (imgSrc) {
            imgSrc = imgSrc.trim();
            if (imgSrc.includes('?')) imgSrc = imgSrc.split('?')[0];
            
            if (!imgSrc.startsWith('http')) {
              if (imgSrc.startsWith('//')) {
                imgSrc = 'https:' + imgSrc;
              } else if (imgSrc.startsWith('/')) {
                imgSrc = 'https://www.flipkart.com' + imgSrc;
              }
            }
            
            // Check if it's a product image (not logo, icon, banner, etc.)
            if (imgSrc && imgSrc.length > 10) {
              const isInvalid = imgSrc.includes('placeholder') || 
                              imgSrc.includes('data:image') ||
                              imgSrc.includes('logo') ||
                              imgSrc.includes('icon') ||
                              imgSrc.includes('banner') ||
                              imgSrc.includes('ad') ||
                              imgSrc.includes('sprite');
              
              const looksValid = imgSrc.includes('.jpg') || 
                               imgSrc.includes('.jpeg') || 
                               imgSrc.includes('.png') || 
                               imgSrc.includes('.webp') || 
                               imgSrc.includes('rukminim') ||
                               imgSrc.includes('img.flipkart') ||
                               imgSrc.includes('flipkart.com') ||
                               (imgSrc.startsWith('http') && imgSrc.length > 30);
              
              if (!isInvalid && looksValid) {
                image = imgSrc;
                console.log(`✅ Found image using page scan (image ${i})`);
                console.log(`   Image URL: ${imgSrc.substring(0, 120)}...`);
                break;
              }
            }
          }
        }
      }
      
      // Method 4: Try to extract from meta tags or JSON-LD
      if (!image) {
        console.log('⚠️  Image scan failed, trying meta tags...');
        // Check og:image meta tag
        const ogImage = $('meta[property="og:image"]').attr('content');
        if (ogImage && ogImage.length > 20 && !ogImage.includes('placeholder')) {
          image = ogImage;
          console.log(`✅ Found image from og:image meta tag`);
          console.log(`   Image URL: ${ogImage.substring(0, 120)}...`);
        } else {
          // Try link rel="image_src"
          const linkImage = $('link[rel="image_src"]').attr('href');
          if (linkImage && linkImage.length > 20) {
            image = linkImage;
            console.log(`✅ Found image from link rel="image_src"`);
          }
        }
      }
      
      // Final check - log image status
      if (image) {
        console.log(`✅✅✅ FINAL: Flipkart image found! Length: ${image.length}`);
        console.log(`   Image URL: ${image.substring(0, 150)}...`);
      } else {
        console.error('❌❌❌ FINAL: No Flipkart image found after all methods!');
        console.error('   This product will be saved WITHOUT an image.');
      }
    } else {
      console.error('Unsupported URL domain. Only Amazon and Flipkart are supported.');
      return null;
    }

    console.log('\n📊 SCRAPING SUMMARY:');
    console.log('   Price:', price || 'NOT FOUND');
    console.log('   Title:', title ? title.substring(0, 50) + '...' : 'NOT FOUND');
    console.log('   Image:', image ? image.substring(0, 100) + '...' : 'NOT FOUND');
    console.log('   Image length:', image ? image.length : 0);
    console.log('   Is Flipkart:', isFlipkart);

    if (isFlipkart && !image) {
      console.error('\n❌❌❌ CRITICAL: Flipkart product image not found!');
      console.error('   This might indicate the selectors need updating.');
      console.error('   URL:', normalizedUrl);
      console.error('   Price found:', !!price);
      console.error('   Title found:', !!title);
      console.error('   Image variable:', image);
    }

    if (!price || price.length === 0) {
      console.error('❌ Price not found. Possible reasons:');
      console.error('1. Website structure changed');
      console.error('2. Product page requires login');
      console.error('3. Product is out of stock');
      console.error('4. URL is invalid or not a product page');
      console.error('5. Amazon is blocking the request');
      
      // Debug: Log page content snippet to help diagnose
      const pageText = $.text().substring(0, 500);
      console.error('   Page content preview:', pageText);
      
      // Check if page contains CAPTCHA or blocking message
      const pageHtml = $.html().toLowerCase();
      const isBlockedPage = pageHtml.includes('captcha') || 
                           pageHtml.includes('robot') || 
                           pageHtml.includes('blocked') ||
                           pageText.includes('sorry, we just need to make sure');
      
      if (isBlockedPage) {
        console.error('   ⚠️  Page appears to be blocked or requires CAPTCHA');
      }
      
      // Check if it's a product page at all
      if (!pageHtml.includes('product') && !pageHtml.includes('price') && !pageHtml.includes('amazon')) {
        console.error('   ⚠️  Page does not appear to be a product page');
      }
      
      // Retry with mobile version if we haven't already
      const shouldRetryMobile = retryCount < MAX_RETRIES && 
                               (normalizedUrl.includes('amazon.in') || normalizedUrl.includes('amazon.com')) && 
                               !normalizedUrl.includes('m.amazon');
      
      if (shouldRetryMobile) {
        console.log(`🔄 Retrying with mobile version...`);
        // Add delay before retry to avoid rate limiting
        await randomDelay(2000, 4000);
        return await scrapeProduct(url, retryCount + 1);
      }
      
      return null;
    }

    const result = { 
      price: price.trim(), 
      title: (title || 'Unknown Product').trim(), 
      image: (image || '').trim() 
    };
    
    console.log('✅ Final scraping result:', {
      price: result.price.substring(0, 30),
      title: result.title.substring(0, 30),
      image: result.image ? result.image.substring(0, 80) + '...' : 'EMPTY',
      imageLength: result.image.length
    });
    
    return result;
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
    
    // Retry with mobile version if we haven't already and it's an Amazon URL
    if (retryCount < MAX_RETRIES && url.includes('amazon.in') && !url.includes('m.amazon.in')) {
      console.log(`🔄 Retrying with mobile version after error...`);
      try {
        return await scrapeProduct(url, retryCount + 1);
      } catch (retryError) {
        console.error('Retry also failed:', retryError.message);
      }
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
    
    // Accept all Amazon variations: amazon.in, amazon.com, amzn.in, amzn.to, m.amazon.in, m.amazon.com
    // Accept all Flipkart variations: flipkart.com, www.flipkart.com, dl.flipkart.com, m.flipkart.com
    const isValidDomain = /(?:amazon\.(?:in|com)|amzn\.(?:in|to)|m\.amazon\.(?:in|com))/.test(hostname) ||
                          /(?:flipkart\.com|dl\.flipkart\.com|m\.flipkart\.com)/.test(hostname);
    
    if (!isValidDomain) {
      return res.status(400).json({ 
        error: 'Only Amazon and Flipkart URLs are supported. Please provide a valid product URL.' 
      });
    }
  } catch (e) {
    return res.status(400).json({ error: 'Invalid URL format. Please provide a valid URL.' });
  }

  console.log('Tracking product from URL:', url);
  
  // Get userId from request body first (needed throughout the function)
  const userId = req.body.userId;
  if (!userId) {
    return res.status(400).json({ error: 'User ID is required' });
  }
  
  // First resolve shortened URLs, then normalize for duplicate check
  // This ensures we check against the same format that will be stored
  const resolvedUrl = await resolveShortUrl(url);
  const normalizedUrlForCheck = normalizeUrl(resolvedUrl) || resolvedUrl || url;
  console.log('Checking for duplicates:');
  console.log('   Original URL:', url);
  console.log('   Resolved URL:', resolvedUrl);
  console.log('   Normalized URL:', normalizedUrlForCheck);
  
  // CRITICAL: Check for duplicate products - MUST prevent duplicates
  // Get ALL products and compare URLs properly (resolve + normalize for each)
  let isDuplicate = false;
  let duplicateProduct = null;
  
  try {
    console.log('🔍 Starting comprehensive duplicate check...');

    // OPTIMIZED: Only check duplicates for the same user (userId filter)
    // This is much faster and ensures proper data isolation
    const userProductsSnapshot = await db.collection('products')
      .where('userId', '==', userId)
      .get();
    
    for (const doc of userProductsSnapshot.docs) {
      const productData = doc.data();
      const existingUrl = productData.url || '';
      
      if (!existingUrl) continue;
      
      // Just normalize existing URL (no resolution needed - stored URLs are already normalized)
      const normalizedExisting = normalizeUrl(existingUrl) || existingUrl;
      
      // Quick comparison - check normalized URLs first (most common case)
      if (normalizedUrlForCheck === normalizedExisting) {
        isDuplicate = true;
        duplicateProduct = {
          id: doc.id,
          title: productData.title,
          url: existingUrl
        };
        console.log('❌ DUPLICATE DETECTED (normalized match)');
        break;
      }
      
      // Also check resolved URL against existing (for edge cases)
      if (resolvedUrl && resolvedUrl !== url && normalizeUrl(resolvedUrl) === normalizedExisting) {
        isDuplicate = true;
        duplicateProduct = {
          id: doc.id,
          title: productData.title,
          url: existingUrl
        };
        console.log('❌ DUPLICATE DETECTED (resolved match)');
        break;
      }
      
      // Final check: original URL against existing (rare case)
      if (url === existingUrl) {
        isDuplicate = true;
        duplicateProduct = {
          id: doc.id,
          title: productData.title,
          url: existingUrl
        };
        console.log('❌ DUPLICATE DETECTED (exact match)');
        break;
      }
    }
    
    if (isDuplicate && duplicateProduct) {
      console.log('❌ Blocking duplicate product addition');
      return res.status(409).json({ 
        error: 'This product is already being tracked',
        existingProductId: duplicateProduct.id,
        existingProductTitle: duplicateProduct.title
      });
    }
    
    console.log('✅ No duplicate found after comprehensive check');
  } catch (checkError) {
    console.error('❌ CRITICAL ERROR in duplicate check:', checkError);
    console.error('Error stack:', checkError.stack);
    // DON'T continue if check fails - return error to be safe
    return res.status(500).json({ 
      error: 'Error checking for duplicates. Please try again.' 
    });
  }

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
  
  // Debug logging for image
  console.log('📸 Image data received from scraping:');
  console.log('   Image URL:', data.image || 'EMPTY');
  console.log('   Image length:', data.image ? data.image.length : 0);
  if (data.image) {
    console.log('   Image preview:', data.image.substring(0, 100) + '...');
  }

  // Validate threshold if provided
  const { thresholdPrice } = req.body;
  let validatedThreshold = null;
  if (thresholdPrice !== undefined && thresholdPrice !== null) {
    const thresholdNum = typeof thresholdPrice === 'number' ? thresholdPrice : parseFloat(thresholdPrice);
    const currentPriceNum = parsePrice(data.price);
    
    if (isNaN(thresholdNum) || thresholdNum <= 0) {
      return res.status(400).json({ error: 'Invalid threshold price' });
    }
    
    if (currentPriceNum !== null && thresholdNum >= currentPriceNum) {
      return res.status(400).json({ 
        error: 'Threshold price must be less than current price' 
      });
    }
    
    validatedThreshold = thresholdNum;
  }

  // FINAL duplicate check right before saving (double safety) - check per user
  try {
    const finalCheck = await db.collection('products')
      .where('url', '==', normalizedUrlForCheck)
      .where('userId', '==', userId)
      .limit(1)
      .get();
    
    if (!finalCheck.empty) {
      const existing = finalCheck.docs[0].data();
      console.log('❌❌❌ FINAL CHECK: Duplicate detected right before save!');
      return res.status(409).json({ 
        error: 'This product is already being tracked',
        existingProductId: finalCheck.docs[0].id,
        existingProductTitle: existing.title
      });
    }
  } catch (finalCheckError) {
    console.error('Error in final duplicate check:', finalCheckError);
    // Still proceed, but log the error
  }

  const now = new Date().toISOString();
  // Store normalized URL to prevent duplicates (use the one we already calculated)
  const finalNormalizedUrl = normalizedUrlForCheck;

  // userId is already declared at the beginning of the function

  const product = {
    url: finalNormalizedUrl, // Store normalized URL to prevent duplicates
    title: data.title,
    price: data.price,
    image: data.image || '', // Ensure image is always a string
    lastChecked: now,
    priceHistory: [{
      price: data.price,
      date: now
    }],
    thresholdPrice: validatedThreshold,
    thresholdReached: false,
    userId: userId // ✅ Store userId with product for filtering
  };

  // Debug: Log what's being saved
  console.log('💾 Saving product to Firestore:');
  console.log('   Title:', product.title);
  console.log('   Price:', product.price);
  console.log('   Image:', product.image || 'EMPTY');
  console.log('   Image length:', product.image ? product.image.length : 0);

  try {
    const docRef = await db.collection('products').add(product);
    console.log('✅ Product added successfully:', product.title);
    console.log('   Product document ID:', docRef.id);
    console.log('   Image saved:', product.image ? 'YES (' + product.image.length + ' chars)' : 'NO');
    // Return the product with the document ID
    res.json({ 
      message: 'Product tracked successfully', 
      product: {
        id: docRef.id,
        ...product
      }
    });
  } catch (error) {
    console.error('Database error:', error.message);
    res.status(500).json({ error: 'Failed to save product: ' + error.message });
  }
});

// Get single product by ID (fast lookup)
app.get('/get-product/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.query.userId;
    
    if (!id) {
      return res.status(400).json({ error: 'Product ID is required' });
    }

    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    const doc = await db.collection('products').doc(id).get();
    
    if (!doc.exists) {
      return res.status(404).json({ error: 'Product not found' });
    }

    const data = doc.data();
    
    // Verify product belongs to requesting user
    if (data.userId !== userId) {
      return res.status(403).json({ error: 'Access denied. Product does not belong to this user.' });
    }

    const product = { 
      id: doc.id, 
      ...data,
      priceHistory: data.priceHistory || [],
      thresholdPrice: data.thresholdPrice || null,
      thresholdReached: data.thresholdReached || false,
      image: data.image || ''
    };
    
    res.json(product);
  } catch (error) {
    console.error('Get product error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

app.get('/get-products', async (req, res) => {
  try {
    const userId = req.query.userId;
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    console.log(`📦 Fetching products for userId: ${userId}`);
    
    // Filter products by userId
    const snapshot = await db.collection('products')
      .where('userId', '==', userId)
      .get();
    
    const products = snapshot.docs.map(doc => {
      const data = doc.data();
      const product = { 
        id: doc.id, 
        ...data,
        priceHistory: data.priceHistory || [],
        thresholdPrice: data.thresholdPrice || null,
        thresholdReached: data.thresholdReached || false,
        hasNotification: data.hasNotification || false,
        notificationType: data.notificationType || null,
        notificationMessage: data.notificationMessage || null,
        notificationTimestamp: data.notificationTimestamp || null,
        image: data.image || '' // Ensure image is always present
      };
      
      // Debug logging for Flipkart products
      if (data.url && data.url.includes('flipkart')) {
        console.log(`📦 Flipkart product retrieved: ${data.title?.substring(0, 30)}`);
        console.log(`   Image: ${product.image ? product.image.substring(0, 80) + '...' : 'EMPTY'}`);
        console.log(`   Image length: ${product.image ? product.image.length : 0}`);
      }
      
      return product;
    });
    
    console.log(`✅ Returning ${products.length} products for userId: ${userId}`);
    res.json(products);
  } catch (error) {
    console.error('❌ Error fetching products:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// Helper function to parse price string to number
function parsePrice(priceStr) {
  try {
    const cleaned = priceStr
      .replace(/₹/g, '')
      .replace(/,/g, '')
      .replace(/Rs\./g, '')
      .replace(/\s/g, '')
      .trim();
    return parseFloat(cleaned);
  } catch (e) {
    return null;
  }
}

// Helper function to send FCM push notification
async function sendFCMNotification(fcmToken, title, body, data = {}) {
  try {
    if (!fcmToken) {
      console.log('⚠️ No FCM token provided, skipping notification');
      return false;
    }

    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      token: fcmToken,
      android: {
        priority: 'high',
        notification: {
          channelId: 'price_alerts',
          sound: 'default',
          priority: 'high',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log(`✅ FCM notification sent successfully: ${response}`);
    return true;
  } catch (error) {
    console.error(`❌ Error sending FCM notification: ${error.message}`);
    // If token is invalid, remove it from database
    if (error.code === 'messaging/invalid-registration-token' || 
        error.code === 'messaging/registration-token-not-registered') {
      console.log(`🗑️ Removing invalid FCM token from database`);
      try {
        const tokensSnapshot = await db.collection('fcm_tokens')
          .where('token', '==', fcmToken)
          .get();
        tokensSnapshot.forEach(async (doc) => {
          await doc.ref.delete();
        });
      } catch (deleteError) {
        console.error(`Error deleting invalid token: ${deleteError.message}`);
      }
    }
    return false;
  }
}

// Helper function to send notifications to all registered FCM tokens
// Send notification to a specific user by userId
async function sendNotificationToUser(userId, title, body, data = {}) {
  try {
    if (!userId) {
      console.log('⚠️ Cannot send notification: userId is required');
      return;
    }
    
    const tokensSnapshot = await db.collection('fcm_tokens')
      .where('userId', '==', userId)
      .get();
      
    if (tokensSnapshot.empty) {
      console.log(`⚠️ No FCM tokens found for userId: ${userId}`);
      return;
    }

    console.log(`📤 Sending notification to ${tokensSnapshot.size} device(s) for userId: ${userId}`);
    const sendPromises = [];
    
    tokensSnapshot.forEach((doc) => {
      const tokenData = doc.data();
      if (tokenData.token) {
        sendPromises.push(sendFCMNotification(tokenData.token, title, body, data));
      }
    });

    const results = await Promise.allSettled(sendPromises);
    const successCount = results.filter(r => r.status === 'fulfilled' && r.value === true).length;
    console.log(`✅ Sent notifications to ${successCount}/${tokensSnapshot.size} devices for userId: ${userId}`);
  } catch (error) {
    console.error(`❌ Error sending notification to user ${userId}: ${error.message}`);
  }
}

// Legacy function - kept for backward compatibility but now filters by userId
async function sendNotificationToAllUsers(title, body, data = {}) {
  // This function is deprecated - use sendNotificationToUser instead
  // But keeping it for backward compatibility
  try {
    const tokensSnapshot = await db.collection('fcm_tokens').get();
    if (tokensSnapshot.empty) {
      console.log('⚠️ No FCM tokens found in database');
      return;
    }

    console.log(`📤 Sending notification to ${tokensSnapshot.size} device(s)`);
    const sendPromises = [];
    
    tokensSnapshot.forEach((doc) => {
      const tokenData = doc.data();
      if (tokenData.token) {
        sendPromises.push(sendFCMNotification(tokenData.token, title, body, data));
      }
    });

    const results = await Promise.allSettled(sendPromises);
    const successCount = results.filter(r => r.status === 'fulfilled' && r.value === true).length;
    console.log(`✅ Sent notifications to ${successCount}/${tokensSnapshot.size} devices`);
  } catch (error) {
    console.error(`❌ Error sending notifications to all users: ${error.message}`);
  }
}

// Helper function to check threshold and price drops, set notification flags
async function checkThresholdAndNotify(docId, product, newPrice, previousPrice) {
  const thresholdPrice = product.thresholdPrice;
  const currentPriceNum = parsePrice(newPrice);
  const previousPriceNum = previousPrice ? parsePrice(previousPrice) : null;
  
  let thresholdReached = false;
  let priceDropped = false;
  let notificationType = null;
  let notificationMessage = null;

  // Check if threshold is reached
  if (thresholdPrice && currentPriceNum !== null) {
    const thresholdNum = typeof thresholdPrice === 'number' ? thresholdPrice : parsePrice(thresholdPrice);
    
    if (thresholdNum !== null) {
      const isThresholdReached = currentPriceNum <= thresholdNum;
      const wasThresholdReached = product.thresholdReached || false;

      // Only notify if threshold is newly reached
      if (isThresholdReached && !wasThresholdReached) {
        thresholdReached = true;
        notificationType = 'threshold_reached';
        notificationMessage = `🎯 Price Alert! ${product.title} dropped to ${newPrice} (Threshold: ₹${thresholdNum.toFixed(0)})`;
        console.log(`🔔 THRESHOLD REACHED for ${product.title}: ${newPrice} <= ₹${thresholdNum}`);
        
        // Send FCM push notification to the product owner
        if (product.userId) {
          await sendNotificationToUser(
            product.userId,
            '🎯 Price Alert!',
            `${product.title} dropped to ${newPrice} (Threshold: ₹${thresholdNum.toFixed(0)})`,
            {
              type: 'threshold_reached',
              productId: docId,
              productTitle: product.title,
              currentPrice: newPrice,
              thresholdPrice: thresholdNum.toString(),
            }
          );
        } else {
          console.warn('⚠️ Cannot send notification: product.userId is missing');
        }
      } else if (isThresholdReached) {
        // Threshold was already reached, just update flag
        thresholdReached = true;
      }
    }
  }

  // Check if price dropped (only if threshold not reached to avoid duplicate notifications)
  if (!thresholdReached && previousPriceNum !== null && currentPriceNum !== null) {
    if (currentPriceNum < previousPriceNum) {
      priceDropped = true;
      if (!notificationType) {
        notificationType = 'price_drop';
        notificationMessage = `📉 Price Drop! ${product.title} dropped from ${previousPrice} to ${newPrice}`;
        console.log(`📉 PRICE DROP for ${product.title}: ${previousPrice} → ${newPrice}`);
        
        // Send FCM push notification to the product owner
        if (product.userId) {
          await sendNotificationToUser(
            product.userId,
            '📉 Price Drop!',
            `${product.title} dropped from ${previousPrice} to ${newPrice}`,
            {
              type: 'price_drop',
              productId: docId,
              productTitle: product.title,
              currentPrice: newPrice,
              previousPrice: previousPrice,
            }
          );
        } else {
          console.warn('⚠️ Cannot send notification: product.userId is missing');
        }
      }
    }
  }

  return {
    thresholdReached,
    priceDropped,
    notificationType,
    notificationMessage
  };
}

// Helper function to update product price with history and check notifications
async function updateProductPrice(docId, newPrice, currentPriceHistory = [], productData = {}) {
  const now = new Date().toISOString();
  const priceHistory = currentPriceHistory || [];
  
  // Get previous price for comparison
  const previousPrice = priceHistory.length > 0 ? priceHistory[priceHistory.length - 1].price : productData.price;
  
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

  // Check for threshold and price drops
  const notificationInfo = await checkThresholdAndNotify(docId, productData, newPrice, previousPrice);
  
  const updateData = {
    price: newPrice,
    lastChecked: now,
    priceHistory: priceHistory,
    thresholdReached: notificationInfo.thresholdReached
  };

  // Add notification flags if there's a notification to show
  if (notificationInfo.notificationType) {
    updateData.hasNotification = true;
    updateData.notificationType = notificationInfo.notificationType;
    updateData.notificationMessage = notificationInfo.notificationMessage;
    updateData.notificationTimestamp = now;
  } else {
    // Clear notification flags if no notification
    updateData.hasNotification = false;
  }
  
  return db.collection('products').doc(docId).update(updateData);
}

app.post('/refresh-product', async (req, res) => {
  const { id, userId } = req.body;
  if (!id) {
    return res.status(400).json({ error: 'Product ID is required' });
  }

  if (!userId) {
    return res.status(400).json({ error: 'User ID is required' });
  }

  try {
    console.log(`🔄 Refreshing product: ${id} for userId: ${userId}`);
    const doc = await db.collection('products').doc(id).get();
    if (!doc.exists) {
      console.error(`❌ Product not found: ${id}`);
      return res.status(404).json({ error: 'Product not found' });
    }

    const product = doc.data();
    
    // Verify product belongs to requesting user
    if (product.userId !== userId) {
      return res.status(403).json({ error: 'Access denied. Product does not belong to this user.' });
    }
    
    // Scrape product (this is the slowest part)
    const newData = await scrapeProduct(product.url);
    
    if (!newData || !newData.price) {
      console.error(`❌ Failed to scrape price for product: ${id}`);
      return res.status(500).json({ error: 'Could not fetch product price' });
    }

    // Update price and history
    await updateProductPrice(id, newData.price, product.priceHistory || [], product);
    
    // Fetch updated document to get latest priceHistory and notification flags
    const updatedDoc = await db.collection('products').doc(id).get();
    const updatedData = updatedDoc.data();
    
    // Merge with new image if available
    if (newData.image) {
      updatedData.image = newData.image;
    }
    
    console.log(`✅ Updated product ${id}: ${newData.price}`);
    res.json({ message: 'Product price updated', product: { id: doc.id, ...updatedData } });
  } catch (error) {
    console.error('❌ Refresh error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// MARK PRODUCT AS BOUGHT - Remove from tracking with congratulations
app.post('/mark-product-bought', async (req, res) => {
  try {
    console.log('\n=== MARK PRODUCT AS BOUGHT ===');
    const { id, userId } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'Product ID is required' });
    }

    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    const searchId = String(id).trim();
    const doc = await db.collection('products').doc(searchId).get();
    
    if (!doc.exists) {
      return res.status(404).json({ error: 'Product not found' });
    }

    const productData = doc.data();
    
    // Verify product belongs to requesting user
    if (productData.userId !== userId) {
      return res.status(403).json({ error: 'Access denied. Product does not belong to this user.' });
    }
    const productTitle = productData.title || 'Product';
    
    // Delete the product
    await db.collection('products').doc(searchId).delete();
    
    console.log(`✅ Product marked as bought and removed: "${productTitle}"`);
    
    res.json({ 
      message: 'Product marked as bought',
      productTitle: productTitle,
      removed: true
    });
  } catch (error) {
    console.error('❌ Mark as bought error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// DELETE PRODUCT - Completely rewritten for reliability
app.post('/delete-product', async (req, res) => {
  try {
    console.log('\n=== DELETE PRODUCT REQUEST ===');
    console.log('Request body:', JSON.stringify(req.body, null, 2));
    
    const { id, userId } = req.body;
    
    if (!id) {
      console.error('❌ Product ID is missing in request body');
      return res.status(400).json({ error: 'Product ID is required' });
    }

    if (!userId) {
      console.error('❌ User ID is missing in request body');
      return res.status(400).json({ error: 'User ID is required' });
    }

    const searchId = String(id).trim();
    console.log(`Searching for product with ID: "${searchId}" for userId: ${userId}`);
    
    // Get product directly by ID (more efficient)
    const doc = await db.collection('products').doc(searchId).get();
    
    if (!doc.exists) {
      console.error(`❌ Product not found with ID: "${searchId}"`);
      return res.status(404).json({ 
        error: 'Product not found',
        searchedId: searchId
      });
    }
    
    const productData = doc.data();
    
    // Verify product belongs to requesting user
    if (productData.userId !== userId) {
      console.error(`❌ Access denied: Product ${searchId} does not belong to userId ${userId}`);
      return res.status(403).json({ error: 'Access denied. Product does not belong to this user.' });
    }
    
    // Delete the product
    const productId = doc.id;
    const productTitle = productData.title || 'Unknown';
    
    console.log(`🗑️  Deleting product: "${productId}" - "${productTitle}"`);
    await db.collection('products').doc(productId).delete();
    
    console.log(`✅ Product deleted successfully: "${productId}"`);
    res.json({ 
      success: true,
      message: 'Product deleted successfully',
      productId: productId
    });
    
  } catch (error) {
    console.error('❌ Delete error:', error.message);
    console.error('Error stack:', error.stack);
    res.status(500).json({ 
      error: 'Failed to delete product: ' + error.message
    });
  }
});

// SET THRESHOLD - Completely rewritten for reliability
app.post('/set-threshold', async (req, res) => {
  try {
    console.log('\n=== SET THRESHOLD REQUEST ===');
    console.log('Request body:', JSON.stringify(req.body, null, 2));
    
    const { id, threshold, userId } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'Product ID is required' });
    }
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }
    
    if (threshold === undefined || threshold === null) {
      return res.status(400).json({ error: 'Threshold price is required' });
    }

    const searchId = String(id).trim();
    const thresholdNum = typeof threshold === 'number' ? threshold : parseFloat(threshold);
    
    if (isNaN(thresholdNum) || thresholdNum <= 0) {
      return res.status(400).json({ error: 'Invalid threshold price. Must be a positive number.' });
    }
    
    console.log(`Searching for product with ID: "${searchId}", threshold: ${thresholdNum}, userId: ${userId}`);
    
    // Get product directly by ID
    const doc = await db.collection('products').doc(searchId).get();
    
    if (!doc.exists) {
      console.error(`❌ Product not found with ID: "${searchId}"`);
      return res.status(404).json({ 
        error: 'Product not found',
        searchedId: searchId
      });
    }
    
    const product = doc.data();
    const productId = doc.id;
    
    // Verify product belongs to requesting user
    if (product.userId !== userId) {
      return res.status(403).json({ error: 'Access denied. Product does not belong to this user.' });
    }
    
    // Validate threshold against current price
    const currentPriceNum = parsePrice(product.price);
    if (currentPriceNum !== null && thresholdNum >= currentPriceNum) {
      return res.status(400).json({ 
        error: `Threshold price (₹${thresholdNum}) must be less than current price (₹${currentPriceNum})` 
      });
    }
    
    console.log(`✅ Setting threshold for product: "${productId}"`);
    console.log(`   Current price: ₹${product.price}`);
    console.log(`   New threshold: ₹${thresholdNum}`);
    
    // Check if threshold is reached
    const thresholdReached = currentPriceNum !== null && currentPriceNum <= thresholdNum;
    
    await db.collection('products').doc(productId).update({
      thresholdPrice: thresholdNum,
      thresholdReached: thresholdReached
    });
    
    console.log(`✅ Threshold set successfully for product: "${productId}"`);
    res.json({ 
      success: true,
      message: 'Threshold price set successfully',
      productId: productId,
      thresholdPrice: thresholdNum
    });
    
  } catch (error) {
    console.error('❌ Set threshold error:', error.message);
    console.error('Error stack:', error.stack);
    res.status(500).json({ 
      error: 'Failed to set threshold: ' + error.message
    });
  }
});

app.post('/remove-threshold', async (req, res) => {
  const { id, userId } = req.body;
  if (!id) {
    return res.status(400).json({ error: 'Product ID is required' });
  }

  if (!userId) {
    return res.status(400).json({ error: 'User ID is required' });
  }

  try {
    const doc = await db.collection('products').doc(id).get();
    
    if (!doc.exists) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    const product = doc.data();
    
    // Verify product belongs to requesting user
    if (product.userId !== userId) {
      return res.status(403).json({ error: 'Access denied. Product does not belong to this user.' });
    }
    
    await db.collection('products').doc(id).update({
      thresholdPrice: null,
      thresholdReached: false
    });
    res.json({ message: 'Threshold removed successfully' });
  } catch (error) {
    console.error('Remove threshold error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// Background job endpoint for cron-job.org
// This endpoint checks all products and updates prices
// Optimized to respond quickly and process in background
app.get('/background-check', async (req, res) => {
  try {
    // Verify API key for security
    const apiKey = req.query.apiKey || req.headers['x-api-key'];
    const validApiKey = '2IcwKctWD2JzIqbPxHhcDN68fxDcxXpCLFLdUQKYbf0=';
    
    if (apiKey !== validApiKey) {
      console.log('❌ Unauthorized background check attempt');
      return res.status(401).json({ error: 'Unauthorized' });
    }

    console.log('\n🔄 Starting background price check...');
    const startTime = Date.now();
    
    // Get products count first
    const snapshot = await db.collection('products').get();
    const totalProducts = snapshot.size;
    console.log(`📦 Found ${totalProducts} product(s) to check`);

    if (totalProducts === 0) {
      return res.json({ 
        message: 'No products to check',
        checked: 0,
        updated: 0,
        failed: 0,
        duration: 0
      });
    }

    // Respond immediately to avoid timeout, then process in background
    res.json({ 
      message: 'Background check started',
      checked: totalProducts,
      status: 'processing',
      startedAt: new Date().toISOString()
    });

    // Process products in background (don't await - let it run async)
    (async () => {
      let updated = 0;
      let failed = 0;
      const errors = [];

      try {
        // Process products with reduced delay (200ms instead of 500ms)
        for (let i = 0; i < snapshot.docs.length; i++) {
          const doc = snapshot.docs[i];
          const product = doc.data();
          
          try {
            console.log(`\n[${i + 1}/${totalProducts}] Checking: ${product.title?.substring(0, 50)}...`);
            
            // Scrape product with timeout
            const newData = await Promise.race([
              scrapeProduct(product.url),
              new Promise((_, reject) => 
                setTimeout(() => reject(new Error('Scrape timeout')), 15000)
              )
            ]);
            
            if (newData && newData.price) {
              // Update product price (this will also check for notifications)
              await updateProductPrice(
                doc.id, 
                newData.price, 
                product.priceHistory || [], 
                product
              );
              updated++;
              console.log(`✅ Updated: ${product.title?.substring(0, 50)} - ${newData.price}`);
            } else {
              failed++;
              errors.push(`${product.title}: Could not fetch price`);
              console.log(`❌ Failed to fetch price for: ${product.title?.substring(0, 50)}`);
            }
            
            // Reduced delay between requests (200ms instead of 500ms)
            if (i < snapshot.docs.length - 1) {
              await new Promise(resolve => setTimeout(resolve, 200));
            }
          } catch (error) {
            failed++;
            const errorMsg = `${product.title}: ${error.message}`;
            errors.push(errorMsg);
            console.error(`❌ Error checking ${product.title?.substring(0, 50)}: ${error.message}`);
            // Continue with next product even if one fails
          }
        }

        const duration = Date.now() - startTime;
        console.log(`\n✅ Background check completed in ${(duration / 1000).toFixed(2)}s`);
        console.log(`   Updated: ${updated}, Failed: ${failed}`);
      } catch (error) {
        console.error('❌ Background processing error:', error.message);
      }
    })();
    
  } catch (error) {
    console.error('❌ Background check error:', error.message);
    if (!res.headersSent) {
      res.status(500).json({ error: error.message });
    }
  }
});

// Legacy endpoint (kept for backward compatibility)
app.get('/scrape-all', async (req, res) => {
  try {
    const snapshot = await db.collection('products').get();
    const updates = [];

    for (const doc of snapshot.docs) {
      const product = doc.data();
      const newData = await scrapeProduct(product.url);
      if (newData && newData.price) {
        updates.push(updateProductPrice(doc.id, newData.price, product.priceHistory || [], product));
      }
    }

    await Promise.all(updates);
    res.json({ message: 'All products updated' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Restore Product Endpoint (fast restore without scraping)
app.post('/restore-product', async (req, res) => {
  try {
    const { productData, userId } = req.body;
    
    if (!productData || !productData.url) {
      return res.status(400).json({ error: 'Product data is required' });
    }

    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    const now = new Date().toISOString();
    const product = {
      url: productData.url,
      title: productData.title || 'Product',
      price: productData.price || '₹0',
      image: productData.image || '',
      lastChecked: productData.lastChecked || now,
      priceHistory: productData.priceHistory || [{
        price: productData.price || '₹0',
        date: productData.lastChecked || now
      }],
      thresholdPrice: productData.thresholdPrice || null,
      thresholdReached: productData.thresholdReached || false,
      userId: userId // ✅ Store userId with restored product
    };

    // Check if product already exists for this user
    const existing = await db.collection('products')
      .where('url', '==', productData.url)
      .where('userId', '==', userId)
      .limit(1)
      .get();

    if (!existing.empty) {
      return res.status(409).json({ 
        error: 'Product already exists',
        product: { id: existing.docs[0].id, ...existing.docs[0].data() }
      });
    }

    const docRef = await db.collection('products').add(product);
    
    res.json({ 
      message: 'Product restored successfully',
      product: {
        id: docRef.id,
        ...product
      }
    });
  } catch (error) {
    console.error('Restore product error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// FCM Token Registration Endpoint
app.post('/register-fcm-token', async (req, res) => {
  try {
    const { token, deviceId, userId } = req.body;
    
    if (!token) {
      return res.status(400).json({ error: 'FCM token is required' });
    }
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    // Check if token already exists
    const existingToken = await db.collection('fcm_tokens')
      .where('token', '==', token)
      .limit(1)
      .get();

    if (!existingToken.empty) {
      // Update existing token with userId
      await existingToken.docs[0].ref.update({
        userId: userId,
        updatedAt: new Date().toISOString(),
        deviceId: deviceId || null,
      });
      console.log(`✅ Updated existing FCM token for userId: ${userId}`);
      return res.json({ message: 'FCM token updated', token: token });
    }

    // Add new token with userId
    await db.collection('fcm_tokens').add({
      token: token,
      userId: userId,
      deviceId: deviceId || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

    console.log(`✅ Registered new FCM token for userId: ${userId}`);
    res.json({ message: 'FCM token registered', token: token });
  } catch (error) {
    console.error('Error registering FCM token:', error.message);
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
  console.log('Background Check Endpoint:');
  console.log(`  GET /background-check?apiKey=YOUR_API_KEY`);
  console.log('========================================');
  console.log('Press Ctrl+C to stop');
  console.log('');
});

// Keep process alive
setInterval(() => { }, 1000);

