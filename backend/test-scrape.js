// Quick test script to verify scraping works
const axios = require('axios');
const cheerio = require('cheerio');

async function testScrape(url) {
  console.log('Testing URL:', url);
  console.log('========================================');
  
  try {
    const headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };

    const { data } = await axios.get(url, {
      headers: headers,
      timeout: 20000,
      maxRedirects: 5
    });

    const $ = cheerio.load(data);
    
    // Test Amazon selectors
    if (url.includes('amazon') || url.includes('amzn.in')) {
      console.log('\n📦 Testing Amazon selectors...');
      
      const priceSelectors = [
        '.a-price .a-offscreen',
        '.a-price-whole',
        '#priceblock_ourprice',
        '.apexPriceToPay .a-offscreen',
        '#corePriceDisplay_desktop_feature_div .a-price .a-offscreen'
      ];
      
      for (const selector of priceSelectors) {
        const found = $(selector).first().text().trim();
        if (found) {
          console.log(`✅ Found price with "${selector}": ${found}`);
          break;
        } else {
          console.log(`❌ Not found: ${selector}`);
        }
      }
      
      const title = $('#productTitle').text().trim();
      if (title) {
        console.log(`✅ Found title: ${title.substring(0, 50)}...`);
      } else {
        console.log('❌ Title not found');
      }
    }
    
    // Test Flipkart selectors
    if (url.includes('flipkart')) {
      console.log('\n📦 Testing Flipkart selectors...');
      
      const price = $('div._30jeq3._16Jk6d').first().text().trim() || 
                    $('._30jeq3').first().text().trim();
      if (price) {
        console.log(`✅ Found price: ${price}`);
      } else {
        console.log('❌ Price not found');
      }
      
      const title = $('span.B_NuCI').text().trim();
      if (title) {
        console.log(`✅ Found title: ${title.substring(0, 50)}...`);
      } else {
        console.log('❌ Title not found');
      }
    }
    
    console.log('\n========================================');
    console.log('✅ Test completed');
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    if (error.response) {
      console.error('Status:', error.response.status);
    }
  }
}

// Get URL from command line argument
const testUrl = process.argv[2];

if (!testUrl) {
  console.log('Usage: node test-scrape.js <URL>');
  console.log('Example: node test-scrape.js "https://www.amazon.in/dp/B08XXXXX"');
  process.exit(1);
}

testScrape(testUrl);

