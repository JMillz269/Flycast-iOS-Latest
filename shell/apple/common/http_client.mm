#import <Foundation/Foundation.h>
#include "oslib/http_client.h"
#include "stdclass.h"
#include <atomic>

namespace http {

static std::atomic<int> cancelGeneration { 0 };

void cancelPending() {
	cancelGeneration++;
}

// Performs the request with NSURLSession, waiting in short slices so the call can be
// aborted by cancelPending() (otherwise a blocked request can stall thread join -> watchdog kill).
static bool sendRequest(NSURLRequest *request, NSData **outData, NSHTTPURLResponse **outResponse)
{
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	config.timeoutIntervalForRequest = 10.0;
	NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	__block NSData *rdata = nil;
	__block NSURLResponse *rresp = nil;
	__block NSError *rerr = nil;
	NSURLSessionDataTask *task = [session dataTaskWithRequest:request
			completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
		rdata = d; rresp = r; rerr = e;
		dispatch_semaphore_signal(sem);
	}];
	int gen = cancelGeneration.load();
	[task resume];
	while (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) != 0)
	{
		if (cancelGeneration.load() != gen) {
			[task cancel];
			dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
			break;
		}
	}
	[session finishTasksAndInvalidate];
	if (rerr != nil || ![rresp isKindOfClass:[NSHTTPURLResponse class]]) {
		NSLog(@"[Flycast] HTTP request failed: %@", rerr);
		return false;
	}
	*outData = rdata;
	*outResponse = (NSHTTPURLResponse *)rresp;
	return true;
}

int get(const std::string& url, std::vector<u8>& content, const Headers *reqHeaders, Headers *respHeaders)
{
	NSString *nsurl = [NSString stringWithCString:url.c_str() 
                                         encoding:[NSString defaultCStringEncoding]];
    NSString *userAgent = [NSString stringWithCString:getUserAgent().c_str()
                                             encoding:[NSString defaultCStringEncoding]];
	NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nsurl]];
	[urlRequest setTimeoutInterval:10.0];
	[urlRequest setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    if (reqHeaders != nullptr)
    {
        for (const auto& [ name, value ] : *reqHeaders)
        {
            NSString *nsname = [NSString stringWithCString:name.c_str()
                                                  encoding:[NSString defaultCStringEncoding]];
            NSString *nsvalue = [NSString stringWithCString:value.c_str()
                                                   encoding:[NSString defaultCStringEncoding]];
            [urlRequest setValue:nsvalue forHTTPHeaderField:nsname];
        }
    }
	NSData *data = nil;
	NSHTTPURLResponse *httpResponse = nil;
	if (!sendRequest(urlRequest, &data, &httpResponse))
		return 500;
	if (respHeaders != nullptr)
	{
		NSDictionary *headers = httpResponse.allHeaderFields;
		NSEnumerator *enumerator = [headers keyEnumerator];
		id key;
		while ((key = [enumerator nextObject]))
		{
			std::string strkey([key UTF8String]);
			string_tolower(strkey);
			std::string strvalue([[headers objectForKey:key] UTF8String]);
			respHeaders->emplace_back(strkey, strvalue);
		}
	}
		
	content.clear();
	content.insert(content.begin(), (const u8 *)[data bytes], (const u8 *)[data bytes] + [data length]);
	
	return [httpResponse statusCode];
}

int post(const std::string& url, const char *payload, const char *contentType, std::vector<u8>& reply)
{
	NSString *nsurl = [NSString stringWithCString:url.c_str() 
                                         encoding:[NSString defaultCStringEncoding]];
    NSString *userAgent = [NSString stringWithCString:getUserAgent().c_str()
                                             encoding:[NSString defaultCStringEncoding]];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nsurl]];
	[request setHTTPMethod:@"POST"];
	[request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
	[request setHTTPShouldHandleCookies:NO];
	[request setTimeoutInterval:10.0];
	
	size_t payloadSize = strlen(payload);
	[request setHTTPBody:[NSData dataWithBytes:payload length:payloadSize]];
	NSString *postLength = [NSString stringWithFormat:@"%ld", (unsigned long)payloadSize];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    NSString *nscontentType = contentType != nullptr ? [NSString stringWithCString:contentType 
                                         encoding:[NSString defaultCStringEncoding]]
    	: @"application/x-www-form-urlencoded";
    [request setValue:nscontentType forHTTPHeaderField:@"Content-Type"];
	[request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    
	NSData *data = nil;
	NSHTTPURLResponse *httpResponse = nil;
	if (!sendRequest(request, &data, &httpResponse))
		return 500;
		
	reply.clear();
	reply.insert(reply.begin(), (const u8 *)[data bytes], (const u8 *)[data bytes] + [data length]);

	return [httpResponse statusCode];
}

int post(const std::string& url, const std::vector<PostField>& fields)
{
	NSString *nsurl = [NSString stringWithCString:url.c_str() 
                                         encoding:[NSString defaultCStringEncoding]];
    NSString *userAgent = [NSString stringWithCString:getUserAgent().c_str()
                                             encoding:[NSString defaultCStringEncoding]];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:nsurl]];
	[request setHTTPMethod:@"POST"];
	[request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
	[request setHTTPShouldHandleCookies:NO];
	[request setTimeoutInterval:10.0];

	NSString *boundary = @"----flycast-boundary-7192397596";
	NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
	[request setValue:contentType forHTTPHeaderField: @"Content-Type"];
	[request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
	
	NSMutableData *body = [NSMutableData data];
	for (const PostField& field : fields)
	{
        NSString *value = [NSString stringWithCString:field.value.c_str() 
                                         encoding:[NSString defaultCStringEncoding]];
		[body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"", [NSString stringWithCString:field.name.c_str() 
                                         encoding:[NSString defaultCStringEncoding]]] dataUsingEncoding:NSUTF8StringEncoding]];
        if (!field.contentType.empty())
        {
	        [body appendData:[[NSString stringWithFormat:@"; filename=\"%@\"\r\n", value] dataUsingEncoding:NSUTF8StringEncoding]];
	        [body appendData:[[NSString stringWithFormat:@"Content-Type: %@", [NSString stringWithCString:field.contentType.c_str() 
                                         encoding:[NSString defaultCStringEncoding]]] dataUsingEncoding:NSUTF8StringEncoding]];
        }
        [body appendData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        
        if (field.contentType.empty())
        {
	        [body appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];
        }
        else
        {
        	NSError* error = nil;
			NSData *filedata = [NSData dataWithContentsOfFile:value options:0 error:&error];
			if (error != nil)
				return 500;
	        [body appendData:filedata];
        }
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	}
	[body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
	
	[request setHTTPBody:body];
	NSString *postLength = [NSString stringWithFormat:@"%ld", (unsigned long)[body length]];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    
	NSData *data = nil;
	NSHTTPURLResponse *httpResponse = nil;
	if (!sendRequest(request, &data, &httpResponse))
		return 500;
	return [httpResponse statusCode];
}

void init() {
}

void term() {
}

}
