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

// Helper function to scrape product
async function scrapeProduct(url) {
  try {
    console.log(`\n🔍 Starting scrape for URL: ${url}`);
    
    // First, resolve shortened URLs (like dl.flipkart.com)
    const resolvedUrl = await resolveShortUrl(url);
    console.log(`📎 Resolved URL: ${resolvedUrl}`);
    
    // Then normalize URL
    const normalizedUrl = normalizeUrl(resolvedUrl);
    console.log(`🔧 Normalized URL: ${normalizedUrl}`);
    console.log(`🌐 Final URL to scrape: ${normalizedUrl}`);

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

    // Check if it's an Amazon URL (all variations)
    // Supports: amazon.in, amazon.com, amzn.in, amzn.to, m.amazon.in, m.amazon.com
    const isAmazon = /(?:amazon\.(?:in|com)|amzn\.(?:in|to)|m\.amazon\.(?:in|com))/.test(normalizedUrl);
    
    // Check if it's a Flipkart URL (all variations)
    // Supports: flipkart.com, www.flipkart.com, dl.flipkart.com, m.flipkart.com
    const isFlipkart = /(?:flipkart\.com|dl\.flipkart\.com|m\.flipkart\.com)/.test(normalizedUrl);
    
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
      console.error('Price not found. Possible reasons:');
      console.error('1. Website structure changed');
      console.error('2. Product page requires login');
      console.error('3. Product is out of stock');
      console.error('4. URL is invalid or not a product page');
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
    const allProducts = await db.collection('products').get();
    console.log(`   Checking against ${allProducts.docs.length} existing products`);
    
    for (const doc of allProducts.docs) {
      const productData = doc.data();
      const existingUrl = productData.url || '';
      
      if (!existingUrl) continue;
      
      // Resolve and normalize existing URL the same way we did for the new URL
      let normalizedExisting = existingUrl;
      try {
        // Try to resolve if it's a shortened URL
        const resolvedExisting = await resolveShortUrl(existingUrl);
        normalizedExisting = normalizeUrl(resolvedExisting) || resolvedExisting || existingUrl;
      } catch (e) {
        // If resolution fails, just normalize
        normalizedExisting = normalizeUrl(existingUrl) || existingUrl;
      }
      
      // Compare all possible URL variations
      const urlVariations = [
        normalizedUrlForCheck,
        resolvedUrl,
        url,
        normalizedExisting,
        existingUrl
      ];
      
      // Check if any variation matches
      for (const newUrlVar of [normalizedUrlForCheck, resolvedUrl, url]) {
        for (const existingUrlVar of [normalizedExisting, existingUrl]) {
          if (newUrlVar && existingUrlVar && newUrlVar === existingUrlVar) {
            isDuplicate = true;
            duplicateProduct = {
              id: doc.id,
              title: productData.title,
              url: existingUrl
            };
            console.log('❌❌❌ DUPLICATE DETECTED!');
            console.log('   New URL (normalized):', normalizedUrlForCheck);
            console.log('   Existing URL:', existingUrl);
            console.log('   Existing URL (normalized):', normalizedExisting);
            console.log('   Match found:', newUrlVar);
            break;
          }
        }
        if (isDuplicate) break;
      }
      
      if (isDuplicate) break;
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

  // FINAL duplicate check right before saving (double safety)
  try {
    const finalCheck = await db.collection('products')
      .where('url', '==', normalizedUrlForCheck)
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
    thresholdReached: false
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

app.get('/get-products', async (req, res) => {
  try {
    const snapshot = await db.collection('products').get();
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
    res.json(products);
  } catch (error) {
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
async function sendNotificationToAllUsers(title, body, data = {}) {
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
        
        // Send FCM push notification
        await sendNotificationToAllUsers(
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
        
        // Send FCM push notification
        await sendNotificationToAllUsers(
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
  const { id } = req.body;
  if (!id) {
    return res.status(400).json({ error: 'Product ID is required' });
  }

  try {
    console.log(`Refreshing product: ${id}`);
    const doc = await db.collection('products').doc(id).get();
    if (!doc.exists) {
      console.error(`Product not found: ${id}`);
      return res.status(404).json({ error: 'Product not found' });
    }

    const product = doc.data();
    console.log(`Scraping URL: ${product.url}`);
    const newData = await scrapeProduct(product.url);
    
    if (!newData || !newData.price) {
      console.error(`Failed to scrape price for product: ${id}`);
      return res.status(500).json({ error: 'Could not fetch product price' });
    }

    console.log(`Updating price for ${id}: ${newData.price}`);
    await updateProductPrice(id, newData.price, product.priceHistory || [], product);
    
    const updatedDoc = await db.collection('products').doc(id).get();
    res.json({ message: 'Product price updated', product: { id: doc.id, ...updatedDoc.data() } });
  } catch (error) {
    console.error('Refresh error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// DELETE PRODUCT - Completely rewritten for reliability
app.post('/delete-product', async (req, res) => {
  try {
    console.log('\n=== DELETE PRODUCT REQUEST ===');
    console.log('Request body:', JSON.stringify(req.body, null, 2));
    
    const { id } = req.body;
    
    if (!id) {
      console.error('❌ Product ID is missing in request body');
      return res.status(400).json({ error: 'Product ID is required' });
    }

    const searchId = String(id).trim();
    console.log(`Searching for product with ID: "${searchId}"`);
    
    // Get ALL products from database
    const allProductsSnapshot = await db.collection('products').get();
    console.log(`📦 Total products in database: ${allProductsSnapshot.size}`);
    
    // Log all products for debugging
    const allProducts = [];
    allProductsSnapshot.docs.forEach((doc, index) => {
      const data = doc.data();
      const productInfo = {
        id: doc.id,
        title: data.title || 'No title',
        url: data.url || 'No URL'
      };
      allProducts.push(productInfo);
      console.log(`  [${index + 1}] ID="${doc.id}" | Title="${productInfo.title}"`);
    });
    
    // Try to find the product - first by exact ID match
    let targetDoc = null;
    let foundById = false;
    
    // Method 1: Exact ID match
    for (const doc of allProductsSnapshot.docs) {
      if (doc.id === searchId) {
        targetDoc = doc;
        foundById = true;
        console.log(`✅ Found product by exact ID match: "${doc.id}"`);
        break;
      }
    }
    
    // Method 2: If not found, try case-insensitive match
    if (!targetDoc) {
      for (const doc of allProductsSnapshot.docs) {
        if (doc.id.toLowerCase() === searchId.toLowerCase()) {
          targetDoc = doc;
          foundById = true;
          console.log(`✅ Found product by case-insensitive ID match: "${doc.id}"`);
          break;
        }
      }
    }
    
    // Method 3: If still not found, try to find by URL (in case ID was corrupted)
    if (!targetDoc) {
      console.log(`⚠️ Product not found by ID, searching all products...`);
      for (const doc of allProductsSnapshot.docs) {
        const data = doc.data();
        // Check if searchId matches URL or title
        if (data.url && data.url.includes(searchId)) {
          targetDoc = doc;
          console.log(`✅ Found product by URL match: "${doc.id}"`);
          break;
        }
      }
    }
    
    if (!targetDoc) {
      console.error(`❌ Product not found with ID: "${searchId}"`);
      console.error('Available product IDs:', allProducts.map(p => p.id).join(', '));
      return res.status(404).json({ 
        error: 'Product not found',
        searchedId: searchId,
        availableIds: allProducts.map(p => p.id)
      });
    }
    
    // Delete the product
    const productId = targetDoc.id;
    const productTitle = targetDoc.data().title || 'Unknown';
    
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
    
    const { id, threshold } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'Product ID is required' });
    }
    
    if (threshold === undefined || threshold === null) {
      return res.status(400).json({ error: 'Threshold price is required' });
    }

    const searchId = String(id).trim();
    const thresholdNum = typeof threshold === 'number' ? threshold : parseFloat(threshold);
    
    if (isNaN(thresholdNum) || thresholdNum <= 0) {
      return res.status(400).json({ error: 'Invalid threshold price. Must be a positive number.' });
    }
    
    console.log(`Searching for product with ID: "${searchId}", threshold: ${thresholdNum}`);
    
    // Get ALL products from database
    const allProductsSnapshot = await db.collection('products').get();
    console.log(`📦 Total products in database: ${allProductsSnapshot.size}`);
    
    // Try to find the product - first by exact ID match
    let targetDoc = null;
    
    // Method 1: Exact ID match
    for (const doc of allProductsSnapshot.docs) {
      if (doc.id === searchId) {
        targetDoc = doc;
        console.log(`✅ Found product by exact ID match: "${doc.id}"`);
        break;
      }
    }
    
    // Method 2: If not found, try case-insensitive match
    if (!targetDoc) {
      for (const doc of allProductsSnapshot.docs) {
        if (doc.id.toLowerCase() === searchId.toLowerCase()) {
          targetDoc = doc;
          console.log(`✅ Found product by case-insensitive ID match: "${doc.id}"`);
          break;
        }
      }
    }
    
    // Method 3: If still not found, try to find by URL
    if (!targetDoc) {
      console.log(`⚠️ Product not found by ID, searching by URL...`);
      for (const doc of allProductsSnapshot.docs) {
        const data = doc.data();
        if (data.url && data.url.includes(searchId)) {
          targetDoc = doc;
          console.log(`✅ Found product by URL match: "${doc.id}"`);
          break;
        }
      }
    }
    
    if (!targetDoc) {
      console.error(`❌ Product not found with ID: "${searchId}"`);
      return res.status(404).json({ 
        error: 'Product not found',
        searchedId: searchId
      });
    }
    
    const product = targetDoc.data();
    const productId = targetDoc.id;
    
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
  const { id } = req.body;
  if (!id) {
    return res.status(400).json({ error: 'Product ID is required' });
  }

  try {
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

// FCM Token Registration Endpoint
app.post('/register-fcm-token', async (req, res) => {
  try {
    const { token, deviceId } = req.body;
    
    if (!token) {
      return res.status(400).json({ error: 'FCM token is required' });
    }

    // Check if token already exists
    const existingToken = await db.collection('fcm_tokens')
      .where('token', '==', token)
      .limit(1)
      .get();

    if (!existingToken.empty) {
      // Update existing token
      await existingToken.docs[0].ref.update({
        updatedAt: new Date().toISOString(),
        deviceId: deviceId || null,
      });
      console.log('✅ Updated existing FCM token');
      return res.json({ message: 'FCM token updated', token: token });
    }

    // Add new token
    await db.collection('fcm_tokens').add({
      token: token,
      deviceId: deviceId || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

    console.log('✅ Registered new FCM token');
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

