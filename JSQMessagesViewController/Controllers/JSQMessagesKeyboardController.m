//
//  Created by Jesse Squires
//  http://www.jessesquires.com
//
//
//  Documentation
//  http://cocoadocs.org/docsets/JSQMessagesViewController
//
//
//  GitHub
//  https://github.com/jessesquires/JSQMessagesViewController
//
//
//  License
//  Copyright (c) 2014 Jesse Squires
//  Released under an MIT license: http://opensource.org/licenses/MIT
//
//
//  Ideas for keyboard controller taken from Daniel Amitay
//  DAKeyboardControl
//  https://github.com/danielamitay/DAKeyboardControl
//

#import "JSQMessagesKeyboardController.h"

#import "UIDevice+JSQMessages.h"


NSString * const JSQMessagesKeyboardControllerNotificationKeyboardDidChangeFrame = @"JSQMessagesKeyboardControllerNotificationKeyboardDidChangeFrame";
NSString * const JSQMessagesKeyboardControllerUserInfoKeyKeyboardDidChangeFrame = @"JSQMessagesKeyboardControllerUserInfoKeyKeyboardDidChangeFrame";

NSString * const kmCustomInputviewDidShow = @"kmCustomInputviewDidShow";
NSString * const kmCustomInputviewDidHide = @"kmCustomInputviewDidHide";

const CGFloat kmInputViewHeight = 216;

static void * kJSQMessagesKeyboardControllerKeyValueObservingContext = &kJSQMessagesKeyboardControllerKeyValueObservingContext;

typedef void (^JSQAnimationCompletionBlock)(BOOL finished);


@interface JSQMessagesKeyboardController () <UIGestureRecognizerDelegate>

@property (assign, nonatomic) BOOL jsq_isObserving;

@property (weak, nonatomic) UIView *keyboardView;

@property (assign, nonatomic) BOOL km_customInput_isObserving;

@property (weak, nonatomic) UIView *cinputView;


- (void)jsq_registerForNotifications;
- (void)jsq_unregisterForNotifications;

- (void)jsq_didReceiveKeyboardDidShowNotification:(NSNotification *)notification;
- (void)jsq_didReceiveKeyboardWillChangeFrameNotification:(NSNotification *)notification;
- (void)jsq_didReceiveKeyboardDidChangeFrameNotification:(NSNotification *)notification;
- (void)jsq_didReceiveKeyboardDidHideNotification:(NSNotification *)notification;
- (void)jsq_handleKeyboardNotification:(NSNotification *)notification completion:(JSQAnimationCompletionBlock)completion;

- (void)jsq_setKeyboardViewHidden:(BOOL)hidden;
- (void)jsq_notifyKeyboardFrameNotificationForFrame:(CGRect)frame;
- (void)jsq_resetKeyboardAndTextView;

- (void)jsq_removeKeyboardFrameObserver;

- (void)jsq_handlePanGestureRecognizer:(UIPanGestureRecognizer *)pan;

@end



@implementation JSQMessagesKeyboardController

#pragma mark - Initialization

- (instancetype)initWithTextView:(UITextView *)textView
                     contextView:(UIView *)contextView
            panGestureRecognizer:(UIPanGestureRecognizer *)panGestureRecognizer
                        delegate:(id<JSQMessagesKeyboardControllerDelegate>)delegate

{
    NSParameterAssert(textView != nil);
    NSParameterAssert(contextView != nil);
    NSParameterAssert(panGestureRecognizer != nil);

    self = [super init];
    if (self) {
        _textView = textView;
        _contextView = contextView;
        _panGestureRecognizer = panGestureRecognizer;
        _delegate = delegate;
        _jsq_isObserving = NO;
		_km_customInput_isObserving = NO;
    }
    return self;
}

- (void)dealloc
{
    [self jsq_removeKeyboardFrameObserver];
    [self jsq_unregisterForNotifications];
	[self km_removeCustomInputViewFrameObserver];
	[self km_unregisterForCustomNotifications];
	
    _textView = nil;
    _contextView = nil;
    _panGestureRecognizer = nil;
    _delegate = nil;
    _keyboardView = nil;
	
	_cinputView = nil;
}

#pragma mark - Setters

- (void)setCinputView:(UIView *)cinputView {
	if (_cinputView) {
		[self km_removeCustomInputViewFrameObserver];
	}
	_cinputView = cinputView;
	
	if (cinputView && !_km_customInput_isObserving) {
		[_cinputView addObserver:self
					  forKeyPath:NSStringFromSelector(@selector(frame))
						 options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:kJSQMessagesKeyboardControllerKeyValueObservingContext];
		
		_km_customInput_isObserving = YES;
	}
}

- (void)setKeyboardView:(UIView *)keyboardView
{
    if (_keyboardView) {
        [self jsq_removeKeyboardFrameObserver];
    }
    _keyboardView = keyboardView;

    if (keyboardView && !_jsq_isObserving) {
        [_keyboardView addObserver:self
                        forKeyPath:NSStringFromSelector(@selector(frame))
                           options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
                           context:kJSQMessagesKeyboardControllerKeyValueObservingContext];

        _jsq_isObserving = YES;
    }
}

#pragma mark - Getters

- (BOOL)keyboardIsVisible
{
    return self.keyboardView != nil;
}

- (BOOL)customInputViewIsVisible {
	return  self.cinputView != nil;
}

- (CGRect)currentKeyboardFrame
{
    if (!self.keyboardIsVisible) {
        return CGRectNull;
    }

    return self.keyboardView.frame;
}

#pragma mark - Keyboard controller

- (void)beginListeningForKeyboard
{
    if (self.textView.inputAccessoryView == nil) {
        self.textView.inputAccessoryView = [[UIView alloc] init];
    }

    [self jsq_registerForNotifications];
	[self km_registerForCustomNotifications];
}

- (void)endListeningForKeyboard
{
    [self jsq_unregisterForNotifications];

    [self jsq_setKeyboardViewHidden:NO];
    self.keyboardView = nil;
}

#pragma mark - Notifications

- (void)jsq_registerForNotifications
{
    [self jsq_unregisterForNotifications];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(jsq_didReceiveKeyboardDidShowNotification:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(jsq_didReceiveKeyboardWillChangeFrameNotification:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(jsq_didReceiveKeyboardDidChangeFrameNotification:)
                                                 name:UIKeyboardDidChangeFrameNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(jsq_didReceiveKeyboardDidHideNotification:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];
}

- (void)jsq_unregisterForNotifications
{
//	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidChangeFrameNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidHideNotification object:nil];
}

//--added keyeMyria
- (void)km_registerForCustomNotifications
{
	[self km_unregisterForCustomNotifications];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(km_didReceiveCustomInputViewDidShowNotification:)
												 name:kmCustomInputviewDidShow object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(km_didReceiveCustomInputViewDidHideNotification:)
												 name:kmCustomInputviewDidHide object:nil];
	
}

- (void)km_unregisterForCustomNotifications
{
//	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:kmCustomInputviewDidShow object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:kmCustomInputviewDidHide object:nil];
}

- (void)km_didReceiveCustomInputViewDidShowNotification:(NSNotification*)notification {
	self.cinputView = self.textView.superview.superview;
	
	[self.panGestureRecognizer addTarget:self action:@selector(km_handlePanGestureRecognizer:)];
}

- (void)km_didReceiveCustomInputViewDidHideNotification:(NSNotification*)notification {
	self.cinputView = nil;
	[self.panGestureRecognizer removeTarget:self action:@selector(km_handlePanGestureRecognizer:)];
}

- (void)km_handlePanGestureRecognizer:(UIPanGestureRecognizer*)pan {
	
	CGPoint touch = [pan locationInView:self.contextView.window];
	CGFloat contextViewWindowHeight = CGRectGetHeight(self.contextView.window.frame);
	if ([UIDevice jsq_isCurrentDeviceBeforeiOS8]) {
		if (UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
			contextViewWindowHeight = CGRectGetWidth(self.contextView.window.frame);
		}
	}
	CGFloat customViewHeight = CGRectGetHeight(self.cinputView.frame);
	CGFloat dragThresholdY = (contextViewWindowHeight - customViewHeight - self.customInputViewTriggerPoint.y);
	
	CGRect newCustomInputviewFrame = self.cinputView.frame;
	
	BOOL userIsDraggingNearThresholdForDismissing = (touch.y > dragThresholdY);
	
	self.cinputView.userInteractionEnabled = !userIsDraggingNearThresholdForDismissing;
//	NSLog(@" %d == = ==  %@ ", pan.state, NSStringFromCGRect(newCustomInputviewFrame));
	switch (pan.state) {
		case UIGestureRecognizerStateChanged: {
			newCustomInputviewFrame.origin.y = touch.y + self.customInputViewTriggerPoint.y;
			newCustomInputviewFrame.origin.y = MIN(newCustomInputviewFrame.origin.y, contextViewWindowHeight);
			newCustomInputviewFrame.origin.y = MAX(newCustomInputviewFrame.origin.y, contextViewWindowHeight - customViewHeight);
			if (CGRectGetMinY(newCustomInputviewFrame) == CGRectGetMinY(self.cinputView.frame)) {
				return;
			}
			[UIView animateWithDuration:0.4
								  delay:0
								options:(UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionTransitionNone) animations:^{
									self.cinputView.frame = newCustomInputviewFrame;
									
								} completion:nil];
		}
			break;
		case UIGestureRecognizerStateEnded:
		case UIGestureRecognizerStateCancelled:
		case UIGestureRecognizerStateFailed: {
			BOOL customInputViewIsHidden = (CGRectGetMaxY(self.cinputView.frame) >= contextViewWindowHeight);
			
			if (customInputViewIsHidden) {
				[self km_resetCustomInputViewAndTextView];
				return;
			}
			CGPoint velocity = [pan velocityInView:self.contextView];
			BOOL userIsScrollingDown = (velocity.y > 0.0f);
			BOOL shouldHide = (userIsScrollingDown && userIsDraggingNearThresholdForDismissing);
			
			newCustomInputviewFrame.origin.y = shouldHide ? contextViewWindowHeight:(contextViewWindowHeight - customViewHeight);
			[UIView animateWithDuration:0.25 delay:0.0 options:(UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationCurveEaseOut) animations:^{
				self.cinputView.frame = newCustomInputviewFrame;
			} completion:^(BOOL finished) {
				self.cinputView.userInteractionEnabled = !shouldHide;
				if (shouldHide) {
					[self km_resetCustomInputViewAndTextView];
				}
			}];
		}
			break;
		default:
			break;
	}
	
}

- (void)jsq_didReceiveKeyboardDidShowNotification:(NSNotification *)notification
{
	self.cinputView = nil;
    self.keyboardView = self.textView.inputAccessoryView.superview;
    [self jsq_setKeyboardViewHidden:NO];

    [self jsq_handleKeyboardNotification:notification completion:^(BOOL finished) {
        [self.panGestureRecognizer addTarget:self action:@selector(jsq_handlePanGestureRecognizer:)];
    }];
}

- (void)jsq_didReceiveKeyboardWillChangeFrameNotification:(NSNotification *)notification
{
    [self jsq_handleKeyboardNotification:notification completion:nil];
}

- (void)jsq_didReceiveKeyboardDidChangeFrameNotification:(NSNotification *)notification
{
    [self jsq_setKeyboardViewHidden:NO];

    [self jsq_handleKeyboardNotification:notification completion:nil];
}

- (void)jsq_didReceiveKeyboardDidHideNotification:(NSNotification *)notification
{
    self.keyboardView = nil;

    [self jsq_handleKeyboardNotification:notification completion:^(BOOL finished) {
        [self.panGestureRecognizer removeTarget:self action:@selector(jsq_handlePanGestureRecognizer:)];
    }];
}

- (void)jsq_handleKeyboardNotification:(NSNotification *)notification completion:(JSQAnimationCompletionBlock)completion
{
    NSDictionary *userInfo = [notification userInfo];

    CGRect keyboardEndFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];

    if (CGRectIsNull(keyboardEndFrame)) {
        return;
    }

    UIViewAnimationCurve animationCurve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    NSInteger animationCurveOption = (animationCurve << 16);

    double animationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];

    CGRect keyboardEndFrameConverted = [self.contextView convertRect:keyboardEndFrame fromView:nil];

    [UIView animateWithDuration:animationDuration
                          delay:0.0
                        options:animationCurveOption
                     animations:^{
                         [self jsq_notifyKeyboardFrameNotificationForFrame:keyboardEndFrameConverted];
                     }
                     completion:^(BOOL finished) {
                         if (completion) {
                             completion(finished);
                         }
                     }];
}

#pragma mark - Utilities

- (void)km_resetCustomInputViewAndTextView {
	self.cinputView = nil;
	[self.delegate resetInputToolbar:self];
	[self km_removeCustomInputViewFrameObserver];
	[self.textView resignFirstResponder];
}

- (void)km_notifyCustomInputViewFrameNotificationForFrame:(CGRect)frame {
	[self.delegate keyboardController:self customInputViewDidChangeFrame:frame];
}

- (void)jsq_setKeyboardViewHidden:(BOOL)hidden
{
    self.keyboardView.hidden = hidden;
    self.keyboardView.userInteractionEnabled = !hidden;
}

- (void)jsq_notifyKeyboardFrameNotificationForFrame:(CGRect)frame
{
    [self.delegate keyboardController:self keyboardDidChangeFrame:frame];

    [[NSNotificationCenter defaultCenter] postNotificationName:JSQMessagesKeyboardControllerNotificationKeyboardDidChangeFrame
                                                        object:self
                                                      userInfo:@{ JSQMessagesKeyboardControllerUserInfoKeyKeyboardDidChangeFrame : [NSValue valueWithCGRect:frame] }];
}

- (void)jsq_resetKeyboardAndTextView
{
    [self jsq_setKeyboardViewHidden:YES];
    [self jsq_removeKeyboardFrameObserver];
    [self.textView resignFirstResponder];
}

#pragma mark - Key-value observing

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == kJSQMessagesKeyboardControllerKeyValueObservingContext) {

        if (object == self.keyboardView && [keyPath isEqualToString:NSStringFromSelector(@selector(frame))]) {
            CGRect oldKeyboardFrame = [[change objectForKey:NSKeyValueChangeOldKey] CGRectValue];
            CGRect newKeyboardFrame = [[change objectForKey:NSKeyValueChangeNewKey] CGRectValue];

            if (CGRectEqualToRect(newKeyboardFrame, oldKeyboardFrame) || CGRectIsNull(newKeyboardFrame)) {
                return;
            }
            
            CGRect keyboardEndFrameConverted = [self.contextView convertRect:newKeyboardFrame
                                                                    fromView:self.keyboardView.superview];
			
            [self jsq_notifyKeyboardFrameNotificationForFrame:keyboardEndFrameConverted];
		} else if (object == self.cinputView && [keyPath isEqualToString:NSStringFromSelector(@selector(frame))]) {
			CGRect oldCustomInputViewFrame = [[change objectForKey:NSKeyValueChangeOldKey] CGRectValue];
			CGRect newCustomInputViewFrame = [[change objectForKey:NSKeyValueChangeNewKey] CGRectValue];
			
			if (CGRectEqualToRect(newCustomInputViewFrame, oldCustomInputViewFrame) || CGRectIsNull(newCustomInputViewFrame)) {
				NSLog(@" --===+++++ ");
				return;
			}
			//TODO
			[self km_notifyCustomInputViewFrameNotificationForFrame:newCustomInputViewFrame];
		}
    }
}

- (void)jsq_removeKeyboardFrameObserver
{
    if (!_jsq_isObserving) {
        return;
    }

    @try {
        [_keyboardView removeObserver:self
                           forKeyPath:NSStringFromSelector(@selector(frame))
                              context:kJSQMessagesKeyboardControllerKeyValueObservingContext];
    }
    @catch (NSException * __unused exception) { }

    _jsq_isObserving = NO;
}

- (void)km_removeCustomInputViewFrameObserver {
	if (!_km_customInput_isObserving) {
		return;
	}
	@try {
		[_cinputView removeObserver:self
						 forKeyPath:NSStringFromSelector(@selector(frame))
							context:kJSQMessagesKeyboardControllerKeyValueObservingContext];
	}
	@catch (NSException *__unused exception) { }
	_km_customInput_isObserving = NO;
}

#pragma mark - Pan gesture recognizer

- (void)jsq_handlePanGestureRecognizer:(UIPanGestureRecognizer *)pan
{
    CGPoint touch = [pan locationInView:self.contextView.window];

    //  system keyboard is added to a new UIWindow, need to operate in window coordinates
    //  also, keyboard always slides from bottom of screen, not the bottom of a view
    CGFloat contextViewWindowHeight = CGRectGetHeight(self.contextView.window.frame);

    if ([UIDevice jsq_isCurrentDeviceBeforeiOS8]) {
        //  handle iOS 7 bug when rotating to landscape
        if (UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
            contextViewWindowHeight = CGRectGetWidth(self.contextView.window.frame);
        }
    }

    CGFloat keyboardViewHeight = CGRectGetHeight(self.keyboardView.frame);

    CGFloat dragThresholdY = (contextViewWindowHeight - keyboardViewHeight - self.keyboardTriggerPoint.y);

    CGRect newKeyboardViewFrame = self.keyboardView.frame;

    BOOL userIsDraggingNearThresholdForDismissing = (touch.y > dragThresholdY);

    self.keyboardView.userInteractionEnabled = !userIsDraggingNearThresholdForDismissing;
	
    switch (pan.state) {
        case UIGestureRecognizerStateChanged:
        {
            newKeyboardViewFrame.origin.y = touch.y + self.keyboardTriggerPoint.y;

            //  bound frame between bottom of view and height of keyboard
            newKeyboardViewFrame.origin.y = MIN(newKeyboardViewFrame.origin.y, contextViewWindowHeight);
            newKeyboardViewFrame.origin.y = MAX(newKeyboardViewFrame.origin.y, contextViewWindowHeight - keyboardViewHeight);

            if (CGRectGetMinY(newKeyboardViewFrame) == CGRectGetMinY(self.keyboardView.frame)) {
                return;
            }

            [UIView animateWithDuration:0.0
                                  delay:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionTransitionNone
                             animations:^{
                                 self.keyboardView.frame = newKeyboardViewFrame;
                             }
                             completion:nil];
        }
            break;

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
        {
            BOOL keyboardViewIsHidden = (CGRectGetMinY(self.keyboardView.frame) >= contextViewWindowHeight);
            if (keyboardViewIsHidden) {
                [self jsq_resetKeyboardAndTextView];
                return;
            }

            CGPoint velocity = [pan velocityInView:self.contextView];
            BOOL userIsScrollingDown = (velocity.y > 0.0f);
            BOOL shouldHide = (userIsScrollingDown && userIsDraggingNearThresholdForDismissing);

            newKeyboardViewFrame.origin.y = shouldHide ? contextViewWindowHeight : (contextViewWindowHeight - keyboardViewHeight);

            [UIView animateWithDuration:0.25
                                  delay:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationCurveEaseOut
                             animations:^{
                                 self.keyboardView.frame = newKeyboardViewFrame;
                             }
                             completion:^(BOOL finished) {
                                 self.keyboardView.userInteractionEnabled = !shouldHide;

                                 if (shouldHide) {
                                     [self jsq_resetKeyboardAndTextView];
                                 }
                             }];
        }
            break;

        default:
            break;
    }
}

@end
