//
//  MUChatKeyboardView.m
//  MUSignal_Example
//
//  Created by Jekity on 2018/6/29.
//  Copyright © 2018年 392071745@qq.com. All rights reserved.
//

#import "MUChatKeyboardView.h"
#import "MUChatKeyboardFaceView.h"
#import "MUEmotionModel.h"
#import "MUEmotionManager.h"
#import "MUHookMethodHelper.h"
#import "MUChatKeyboardMoreView.h"
#import "MUChatKeyboardMoreViewItem.h"

#define menuHeightMU  49.
#define buttonHeightMU  38.
#define margainMU  6.5

typedef NS_ENUM(NSInteger, MUChatKeyboardStatus) {
    MUChatKeyboardStatusNothing = 0,     // 默认状态
    MUChatKeyboardStatusRecord,          // 录音状态
    MUChatKeyboardStatusFace,            // 输入表情状态
    MUChatKeyboardStatusMore,           // 显示“更多”页面状态
    MUChatKeyboardStatusNormal,         // 正常键盘
    MUChatKeyboardStatusVideo          // 录制视频
};

@interface MUChatKeyboardView() <UITextViewDelegate>

@property(nonatomic,strong)UITextView *textView;
@property(nonatomic,strong)UIView *menuContainer;//菜单容器
@property(nonatomic,strong)UIView *contentCotainer;//内容容器

/** 分割线 */
@property(nonatomic,strong)UIView *topLine;

/** 录音按钮 */
@property(nonatomic,strong)UIButton *voiceButton;
/** 表情按钮 */

@property(nonatomic,strong)UIButton *faceButton;
/** (+)按钮 */
@property(nonatomic,strong)UIButton *moreButton;
/** 按住说话 */
@property(nonatomic,strong)UIButton *talkButton;

@property (nonatomic,assign) CGFloat keyboardY;

@property (nonatomic,weak) UIViewController *weakViewController;

@property (nonatomic,assign) MUChatKeyboardStatus keyBoardStatus;

@property(nonatomic,strong)MUChatKeyboardFaceView *faceView;
@property(nonatomic,strong)MUChatKeyboardMoreView *moreView;

@property (nonatomic,assign) CGFloat keyboardHeight;

@property (nonatomic,assign) BOOL ignoredOffsetY;
@property (nonatomic,assign) BOOL ignoredHeight;

@end


static __weak MUChatKeyboardView *weakKeyBoardView = nil;
@implementation MUChatKeyboardView
+(void)load{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [MUHookMethodHelper muHookMethod:NSStringFromClass([UITextView class]) orignalSEL:@selector(deleteBackward) newClassName:NSStringFromClass([self class]) newSEL:@selector(MUKeyboardDeleteBackward)];
    });
}
- (instancetype)initWithFrame:(CGRect)frame{
    frame.size.height = menuHeightMU;
    if (self = [super initWithFrame:frame]) {
        weakKeyBoardView = self;
        _ignoredHeight = NO;
        _ignoredOffsetY = NO;
        self.backgroundColor = [UIColor colorWithRed:241./255. green:241./255. blue:241./255. alpha:1.];
        if (iPhoneX) {
            _keyboardHeight = 333.;
            
        }else if (iPhone6P){
            _keyboardHeight = 271.;
        }else if (iPhone6){
            _keyboardHeight = 258.;
        }
        else{
            _keyboardHeight = 253.;
        }
        [self configuredUI];
        _keyBoardStatus = MUChatKeyboardStatusNothing;
        [self addNotification];
    }
    return self;
}
-(CGFloat)keyboardHeightMU{
    
    return _keyboardHeight;
}
- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)addNotification{
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChangeFrameShow:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHide:) name:UIKeyboardWillHideNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emotionDidSelected:) name:MUEmotionDidSelectNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deleteBtnClicked:) name:MUEmotionDidDeleteNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sendMessage) name:MUEmotionDidSendNotification object:nil];
}


-(void)setShowKeyboard:(BOOL)showKeyboard{
    _showKeyboard = showKeyboard;
    if (!showKeyboard&&(self.keyBoardStatus != MUChatKeyboardStatusNothing)) {
        self.keyBoardStatus = MUChatKeyboardStatusNothing;
        
    }
}
#pragma mark 通知 --选择表情
- (void)emotionDidSelected:(NSNotification *)notifi
{
    
    id  object = notifi.userInfo[MUSelectEmotionKey];
    if ([object isKindOfClass:[MUModel class]]) {
//        MUModel  *emotion = object;
//        if (emotion.emName) {
//            [self.textView insertText:[NSString stringWithFormat:@"[%@]",emotion.emName]];
//        }
//
        
    }else{
        
        MUEmotionModel  *emotion = object;
        if (emotion.code) {
            [self.textView insertText:emotion.code.emoji];
        } else if (emotion.face_name) {
            [self.textView insertText:emotion.face_name];
        }
        
    }
}
#pragma mark --发送消息---
- (void)sendMessage
{
    if (self.textView.text.length >0) {
        [self resetFrame];
        if (self.sendMessageCallback) {
            self.sendMessageCallback([self customingFaceWithAttributeString:self.textView.text]);
        }
    }
    self.textView.text = @"";
}
-(NSString *)customingFaceWithAttributeString:(NSString *)message{
    
    
    if (message.length == 0) {
        
        return @"";
        
    }
    NSMutableAttributedString *mAttributeString = [[NSMutableAttributedString alloc]initWithString:message];
    NSString *pattern =  @"\\[([a-zA-Z0-9\\/\\u4e00-\\u9fa5]+)\\]";
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern: pattern options: NSRegularExpressionCaseInsensitive error: &error];
    if (!regex) {
        NSLog(@"%@",error);
    }
    NSArray *match = [regex matchesInString: message options:NSMatchingReportProgress range: NSMakeRange(0, [message length])];
    NSMutableArray *mutableArray = [NSMutableArray arrayWithCapacity:match.count];
//    for (NSTextCheckingResult*result in match) {
//        NSString *tagValue = [message substringWithRange:[result rangeAtIndex:1]];  // 分组2所对应的串
//        NSArray *faceArr = [MUEmotionManager faceWithCustoming];
//        for (MUModel *face in faceArr) {
//            if ([face.emName isEqualToString:tagValue]) {
//                NSAttributedString *imgStr = [[NSAttributedString alloc]initWithString:face.emCode];
//                NSDictionary *imagDic   = @{@"range":[NSValue valueWithRange:result.range],@"name":imgStr};
//                [mutableArray addObject:imagDic];
//            }
//        }
//
//    }
    for (int i =(int) mutableArray.count - 1; i >= 0; i --) {
        NSRange range;
        [mutableArray[i][@"range"] getValue:&range];
        [mAttributeString replaceCharactersInRange:range withAttributedString:mutableArray[i][@"name"]];
    }
    return mAttributeString.string;
}
#pragma mark -监听删除
- (void) MUKeyboardDeleteBackward{
    if ([weakKeyBoardView respondsToSelector:@selector(deleteBtnClicked:)]) {
        
        if (![weakKeyBoardView fiflterMessageTextView:weakKeyBoardView.textView]) {
            [self MUKeyboardDeleteBackward];
        }
    }else{
        [self MUKeyboardDeleteBackward];
    }
}
#pragma mark 通知 --- 删除--回退--
- (void)deleteBtnClicked:(NSNotification *)notifi
{
    if ( ![self fiflterMessageTextView:self.textView]) {
        [self.textView deleteBackward];
    }
    
    
}
- (BOOL)fiflterMessageTextView:(UITextView *)textView

{
    NSString *regEmj  =  @"\\[([a-zA-Z0-9\\/\\u4e00-\\u9fa5]+)\\]";// [微笑]、［哭］等自定义表情处理
    NSError *error    = nil;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regEmj options:NSRegularExpressionCaseInsensitive error:&error];
    BOOL reslut = NO;
    if (!expression) {
        
        return reslut;
    }
    NSArray *resultArray = [expression matchesInString:textView.text options:0 range:NSMakeRange(0, textView.text.length)];
    if (!resultArray || resultArray.count == 0) {
        return reslut;
    }
//    for (NSTextCheckingResult *match in resultArray) {
//        NSRange range    = match.range;
//        NSString *subStr = [textView.text substringWithRange:[match rangeAtIndex:1]];
//        NSArray *faceArr = [MUEmotionManager faceWithCustoming];
//        for (MUModel *face in faceArr) {
//            if ([face.emName isEqualToString:subStr] && [self rangeComparedRange:range comparedRange:textView.selectedRange]) {
//                textView.text = [textView.text stringByReplacingCharactersInRange:range withString:@""];
//                textView.selectedRange = NSMakeRange(range.location, 0);
//                reslut = YES;
//                return reslut;
//
//            }
//        }
//
//    }
    return reslut;
}
- (BOOL) rangeComparedRange:(NSRange)originalRang comparedRange:(NSRange)comparedRange{
    
    if ((originalRang.location + originalRang.length) == (comparedRange.location + comparedRange.length)) {
        return YES;
    }else{
        return NO;
    }
}
- (UIViewController *)weakViewController{
    if (!_weakViewController) {
        [self getViewControllerFromCurrentView];
    }
    return _weakViewController;
}
-(void)getViewControllerFromCurrentView{
    
    UIResponder *nextResponder = self.nextResponder;
    while (nextResponder != nil) {
        if ([nextResponder isKindOfClass:[UINavigationController class]]) {
            _weakViewController = nil;
            break;
        }
        if ([nextResponder isKindOfClass:[UIViewController class]]) {
            
            _weakViewController = (UIViewController*)nextResponder;
            break;
            
        }
        
        nextResponder = nextResponder.nextResponder;
    }
}

/**------------------------键盘逻辑------------------------------*/
- (void)autoAdjustContentOffsetY{
    if (_keyBoardStatus == MUChatKeyboardStatusNothing || _keyBoardStatus == MUChatKeyboardStatusRecord) {
        [self scrollToBottom:NO heigh:self.height_Mu];
    }else {
        [self scrollToBottom:YES heigh:menuHeightMU+_keyboardHeight];
    }
}

//滚动到底部
- (void)scrollToBottom:(BOOL)ignored heigh:(CGFloat)height{
    
    if (!CGSizeEqualToSize(self.adjustView.contentSize, CGSizeZero)) {
        
        CGFloat margain = kScreenHeight - self.weakViewController.navigationBarAndStatusBarHeight - height;
        if (self.adjustView.contentSize.height > margain) {
            CGPoint bottomOffset = CGPointMake(0, self.adjustView.contentSize.height - self.adjustView.bounds.size.height);
            [self.adjustView setContentOffset:bottomOffset animated:NO];//滚动到底部
        }else{
            [UIView animateWithDuration:.25 animations:^{
                
                self.adjustView.offsetYMu = 0;
            }];

        }
    }
}
- (void)keyboardChangeFrameShow:(NSNotification *)note{
    CGRect keyBoardRect=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat deltaY=keyBoardRect.size.height;
    if (keyBoardRect.origin.y < kScreenHeight) {//显示
        if (!isShowKeyboard) {
            return;
        }
        isShowKeyboard = NO;
         CGFloat margain = deltaY - _keyboardHeight;
        _keyboardHeight = deltaY;
        _keyBoardStatus = MUChatKeyboardStatusNormal;
      
        [UIView animateWithDuration:0.25 animations:^{
            self.transformedView.transform=CGAffineTransformIdentity;
            self.transformedView.transform =  CGAffineTransformMakeTranslation(0, -_keyboardHeight);
//            self.transformedView.y_Mu = -_keyboardHeight;
            if (_ignoredOffsetY) {
                self.adjustView.offsetYMu -= margain;
            }
            if (_ignoredHeight) {
                self.transformedView.height_Mu += margain;
                self.height_Mu = self.menuContainer.height_Mu + margain;
            }
            
            if ([self judgeRemainHeightIfMoreThanHeight:self.menuContainer.height_Mu+_keyboardHeight]) {
                
                [self scrollToBottom:YES heigh:self.menuContainer.height_Mu+_keyboardHeight];
            }
        }];
    }
    
}
static BOOL isShowKeyboard = NO;
-(void)keyboardShow:(NSNotification *)note
{
    if (![self.textView isFirstResponder]||isShowKeyboard) {//去掉其它键盘弹起影响
        return;
    }
    isShowKeyboard = YES;
      CGRect keyBoardRect=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
     CGFloat deltaY=keyBoardRect.size.height;
   
    _keyboardHeight = deltaY;
    
    _keyBoardStatus = MUChatKeyboardStatusNormal;
     [self adjustPosition:_ignoredHeight offsetY:_ignoredOffsetY];
    _ignoredOffsetY = YES;
    _ignoredHeight = NO;
}
-(void)keyboardHide:(NSNotification *)note
{
    if (!isShowKeyboard) {
        return;
    }
    isShowKeyboard = NO;
    double duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] floatValue];
    switch (self.keyBoardStatus) {
        case MUChatKeyboardStatusNothing:
        {
            [self recoveredPosition:_ignoredOffsetY duration:duration];
            _ignoredOffsetY = _ignoredHeight = NO;
        }
        break;
        case MUChatKeyboardStatusNormal:
        {
            [self recoveredPosition:_ignoredOffsetY duration:duration];
             _ignoredOffsetY = _ignoredHeight = NO;
        }
            break;
        case MUChatKeyboardStatusFace:
        {
             [self adjustPosition:_ignoredHeight offsetY:_ignoredOffsetY];
             _ignoredOffsetY = _ignoredHeight = YES;
        }
            break;
     
        case MUChatKeyboardStatusMore:
        {
             [self adjustPosition:_ignoredHeight offsetY:_ignoredOffsetY];
             _ignoredOffsetY = _ignoredHeight = YES;
        }
            break;
        case MUChatKeyboardStatusRecord:
        {
            
         [self recoveredPosition:_ignoredOffsetY duration:duration];
             _ignoredOffsetY = _ignoredHeight = NO;
            
        }
            break;
        default:
        {
            [UIView animateWithDuration:[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] floatValue] animations:^{
                self.transformedView.transform = CGAffineTransformIdentity;
//                self.transformedView.y_Mu = 0;
            }];
        }
            break;
    }
}
- (void)setKeyBoardStatus:(MUChatKeyboardStatus)keyBoardStatus{
    if (_keyBoardStatus == keyBoardStatus) {
        return;
    }
    _keyBoardStatus = keyBoardStatus;
    switch (keyBoardStatus) {
        case MUChatKeyboardStatusNothing:
        {
            
            self.height_Mu = self.menuContainer.height_Mu + _keyboardHeight;
            self.faceView.hidden = self.moreView.hidden = YES;
            
            if (self.textView.isFirstResponder) {
                [self.textView resignFirstResponder];
            }else{
              
                [self recoveredPosition:_ignoredOffsetY duration:.25];
                _ignoredOffsetY = _ignoredHeight = NO;
            }
        }
            break;
        case MUChatKeyboardStatusNormal:
        {
            
            self.faceView.hidden = self.moreView.hidden = YES;
            self.voiceButton.selected = NO;
            self.textView.hidden = NO;
            self.talkButton.hidden = YES;
            self.faceButton.selected= NO;
            if (!self.textView.isFirstResponder) {
                
                [self.textView becomeFirstResponder];
            }
        }
            break;
        case MUChatKeyboardStatusRecord:
        {
            
            self.faceView.hidden = self.moreView.hidden = YES;
            self.voiceButton.selected = YES;
            self.faceButton.selected =  self.moreButton.selected = NO;
            self.talkButton.hidden = NO;
            self.textView.hidden = YES;
            if (self.textView.isFirstResponder) {
                [self.textView resignFirstResponder];
            }else{
                 [self recoveredPosition:_ignoredOffsetY duration:.25];
                 _ignoredOffsetY = _ignoredHeight = NO;
            }
        }
            break;
        case MUChatKeyboardStatusFace:
        {
            
            self.moreView.hidden = YES;
            self.faceView.hidden = NO;
            self.voiceButton.selected = NO;
            self.talkButton.hidden = YES;
            self.moreButton.selected = NO;
            self.textView.hidden = NO;
            
            if (self.textView.isFirstResponder) {
                [self.textView resignFirstResponder];
            }else{
                [self adjustPosition:_ignoredHeight offsetY:_ignoredOffsetY];
                _ignoredOffsetY = _ignoredHeight = YES;
            }
        }
            break;
            
        case MUChatKeyboardStatusMore:
        {
            self.moreView.hidden = NO;
            self.faceView.hidden = YES;
            self.voiceButton.selected = NO;
            self.talkButton.hidden = YES;
            self.textView.hidden = NO;
            self.faceButton.selected =  NO;
            if (self.textView.isFirstResponder) {
                [self.textView resignFirstResponder];
            }else{
                [self adjustPosition:_ignoredHeight offsetY:_ignoredOffsetY];
                 _ignoredOffsetY = _ignoredHeight = YES;
            }
            
        }
            break;
        default:
            break;
    }
}
- (void) recoveredPosition:(BOOL)ignored  duration:(CGFloat)duration{
    [UIView animateWithDuration:duration animations:^{
        
        self.transformedView.transform = CGAffineTransformIdentity;
        self.adjustView.transform = CGAffineTransformIdentity;
//        self.transformedView.y_Mu = 0;
//        self.adjustView.y_Mu = 0;
        if (ignored) {//偏移过
            self.adjustView.offsetYMu += _keyboardHeight;
        }
        if (_keyBoardStatus == MUChatKeyboardStatusRecord || _keyBoardStatus == MUChatKeyboardStatusNothing) {
            if (self.height_Mu > _keyboardHeight) {
                self.transformedView.height_Mu -= _keyboardHeight;
                self.height_Mu -= _keyboardHeight;
            }
            if (_keyBoardStatus == MUChatKeyboardStatusRecord) {
                CGFloat margain = self.menuContainer.height_Mu - menuHeightMU;
                self.y_Mu += margain;
                self.height_Mu = menuHeightMU;
                self.menuContainer.height_Mu = menuHeightMU;
                _voiceButton.y_Mu = _faceButton.y_Mu = _moreButton.y_Mu = menuHeightMU - margainMU - 36.;
                [self scrollToBottom:YES heigh:menuHeightMU];
            }else{
                CGFloat margain = self.menuContainer.height_Mu - menuHeightMU;
                [UIView animateWithDuration:.25 animations:^{
                    self.adjustView.transform = CGAffineTransformIdentity;
                    self.adjustView.transform = CGAffineTransformMakeTranslation(0, -margain);
//                    self.adjustView.y_Mu = - margain;
                }];
            }
        }
    }];
}
- (void) adjustPosition:(BOOL)ignored offsetY:(BOOL)offsetY{
    [UIView animateWithDuration:0.25 animations:^{
        self.transformedView.transform=CGAffineTransformIdentity;
        self.transformedView.transform =  CGAffineTransformMakeTranslation(0, -_keyboardHeight);
//        self.transformedView.y_Mu = - _keyboardHeight;
        if (!offsetY) {
            self.adjustView.offsetYMu -= _keyboardHeight;
        }
        if (!ignored) {
            self.transformedView.height_Mu += _keyboardHeight;
            self.height_Mu = self.menuContainer.height_Mu + _keyboardHeight;
        }
        if ([self judgeRemainHeightIfMoreThanHeight:self.menuContainer.height_Mu+_keyboardHeight]) {
            CGPoint bottomOffset = CGPointMake(0, self.adjustView.contentSize.height - self.adjustView.bounds.size.height);
            [self.adjustView setContentOffset:bottomOffset animated:NO];//滚动到底部
        }
    }];
}

-(void)voiceResetFrame
{
    
    self.talkButton.frame = CGRectMake(buttonHeightMU + 6., (menuHeightMU - 36.)/2, kScreenWidth -3 * buttonHeightMU - 2 * 6., 36.);
    self.voiceButton.frame = CGRectMake(0, (menuHeightMU - buttonHeightMU)/2, buttonHeightMU, buttonHeightMU);
    self.faceButton.frame =CGRectMake(kScreenWidth -2 * buttonHeightMU, (menuHeightMU - buttonHeightMU)/2, buttonHeightMU, buttonHeightMU);
    self.moreButton.frame =CGRectMake(kScreenWidth - buttonHeightMU, (menuHeightMU - buttonHeightMU)/2, buttonHeightMU, buttonHeightMU);
    
}
- (BOOL)judgeRemainHeightIfMoreThanHeight:(CGFloat)height{
    if (!CGSizeEqualToSize(self.adjustView.contentSize, CGSizeZero)) {
        
        CGFloat margain = kScreenHeight - self.weakViewController.navigationBarAndStatusBarHeight - height;
        if (self.adjustView.contentSize.height > margain) {
            return YES;
        }
    }
    return NO;
}
#pragma mark -textView delegate
-(void)textViewDidChange:(UITextView *)textView{
    CGFloat textHeight = ceil([textView sizeThatFits:textView.frame.size].height)+margainMU*2;//更改后的高度
    CGFloat height = menuHeightMU;//原始高度
    BOOL ignoredHeight = NO;
    if (_keyBoardStatus == MUChatKeyboardStatusFace || _keyBoardStatus == MUChatKeyboardStatusMore) {
        ignoredHeight = YES;//增加过高度
    }
    if (textHeight <= 88.) {//最大高度为128.
        if (textHeight <= height) {
            [self resetFrame];
        }else {
            CGFloat margain = textHeight - height;
            CGFloat padding = textHeight - self.menuContainer.height_Mu;
            [UIView animateWithDuration:.25 animations:^{
                self.menuContainer.height_Mu = textHeight;
                self.y_Mu -= padding;
                self.contentCotainer.y_Mu    = textHeight;
                self.textView.height_Mu      = textHeight - margainMU*2;
                _voiceButton.y_Mu = _faceButton.y_Mu = _moreButton.y_Mu = textHeight - margainMU - 36.;
                if ([self judgeRemainHeightIfMoreThanHeight:self.menuContainer.height_Mu + _keyboardHeight ]) {
                    
                    self.adjustView.transform = CGAffineTransformIdentity;
                    self.adjustView.transform = CGAffineTransformMakeTranslation(0, -margain);
//                    self.adjustView.y_Mu = -margain;
                }
                self.height_Mu += padding;
                
            }];

            }
    }
    [self.textView scrollRangeToVisible:NSMakeRange(0, self.textView.text.length)];
    
}
- (void)resetFrame{
   
    CGFloat padding =  self.menuContainer.height_Mu - menuHeightMU;
    [UIView animateWithDuration:.25 animations:^{
        self.y_Mu += padding;
        _voiceButton.y_Mu = _faceButton.y_Mu = _moreButton.y_Mu = menuHeightMU - margainMU - 36.;
        self.contentCotainer.y_Mu    = menuHeightMU;
         self.textView.height_Mu =  36.;
        self.adjustView.transform = CGAffineTransformIdentity;
//        self.adjustView.y_Mu = 0;
        self.menuContainer.height_Mu = menuHeightMU;
    }];
        
    
}
-(BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text{
    
    if ([text isEqualToString:@"\n"]) {
        [self resetFrame];
        if (self.textView.text.length >0) {
            if (self.sendMessageCallback) {
                self.sendMessageCallback(self.textView.text);
            }
        }
        self.textView.text = @"";
        return NO;
    }
    return YES;
}

- (void)configuredUI{
    [self addSubview:self.contentCotainer];
    [self addSubview:self.menuContainer];
    [self.menuContainer addSubview:self.topLine];
    [self.menuContainer addSubview:self.voiceButton];
    [self.menuContainer addSubview:self.faceButton];
    [self.menuContainer addSubview:self.moreButton];
    [self.menuContainer addSubview:self.textView];
    [self.menuContainer addSubview:self.talkButton];
    
    [self.contentCotainer addSubview:self.faceView];
    [self.contentCotainer addSubview:self.moreView];
}
#pragma mark - method
- (void)voiceButtonDown:(UIButton *)button{
    button.selected = !button.selected;
    if (button.selected) {
        self.keyBoardStatus = MUChatKeyboardStatusRecord;
    }else{
        
        [self textViewDidChange:_textView];
        self.keyBoardStatus = MUChatKeyboardStatusNormal;
    }
    
}
- (void)faceButtonDown:(UIButton *)button{
    
    if (self.textView.text.length > 0) {
        //        [self textViewDidChange:_textView];
        [self.textView scrollRangeToVisible:NSMakeRange(0, self.textView.text.length)];
    }
    button.selected = !button.selected;
    if (self.keyBoardStatus == MUChatKeyboardStatusFace) {
        self.keyBoardStatus = MUChatKeyboardStatusNormal;
        button.selected = NO;
    }else{
        
        if (button.selected) {
            self.keyBoardStatus = MUChatKeyboardStatusFace;
            
        }else{
            self.keyBoardStatus = MUChatKeyboardStatusNormal;
        }
    }
}
- (void)moreButtonDown:(UIButton *)button{
    button.selected = !button.selected;
    if (button.selected) {
        self.keyBoardStatus = MUChatKeyboardStatusMore;
    }else{
        self.keyBoardStatus = MUChatKeyboardStatusNormal;
    }
    
}
//菜单容器
- (UIView *)menuContainer{
    
    if (!_menuContainer) {
        _menuContainer = [[UIView alloc]initWithFrame:CGRectMake(0, 0, kScreenWidth, menuHeightMU)];
        _menuContainer.backgroundColor = [UIColor clearColor];
    }
    return _menuContainer;
}

//内容容器
- (UIView *)contentCotainer{
    if (!_contentCotainer) {
        _contentCotainer = [[UIView alloc]initWithFrame:CGRectMake(0, menuHeightMU, kScreenWidth, _keyboardHeight)];
        _contentCotainer.backgroundColor = [UIColor clearColor];
    }
    return _contentCotainer;
}

-(MUChatKeyboardFaceView *)faceView{
    if (!_faceView ) {
        _faceView =[[MUChatKeyboardFaceView alloc]initWithFrame:CGRectMake(0, 0, kScreenWidth, _keyboardHeight)];
        
    }
    return _faceView;
}
-(MUChatKeyboardMoreView *)moreView{
    if (!_moreView ) {
        _moreView =[[MUChatKeyboardMoreView alloc]initWithFrame:CGRectMake(0, 0, kScreenWidth, _keyboardHeight)];
        _moreView.hidden = YES;
        // 创建Item
        MUChatKeyboardMoreViewItem *photosItem = [MUChatKeyboardMoreViewItem createChatBoxMoreItemWithTitle:@"照片"
                                                                                                  imageName:@"sharemore_pic"];
        MUChatKeyboardMoreViewItem *takePictureItem = [MUChatKeyboardMoreViewItem createChatBoxMoreItemWithTitle:@"拍摄"
                                                                                                       imageName:@"sharemore_video"];
        MUChatKeyboardMoreViewItem *videoItem = [MUChatKeyboardMoreViewItem createChatBoxMoreItemWithTitle:@"小视频"
                                                                                                 imageName:@"sharemore_sight"];
        MUChatKeyboardMoreViewItem *docItem   = [MUChatKeyboardMoreViewItem createChatBoxMoreItemWithTitle:@"文件" imageName:@"sharemore_wallet"];
        [_moreView setItems:[[NSMutableArray alloc] initWithObjects:photosItem, takePictureItem, videoItem,docItem, nil]];
        
        weakify(self)
        _moreView.itemByTaped = ^(NSUInteger currentTag) {
            normalize(self)
            if (self.moreViewItemByClicked) {
                self.moreViewItemByClicked(currentTag);
            }
            
            
        };
        //        _moreView.backgroundColor =[UIColor purpleColor];
    }
    return _moreView;
}
//键盘顶部分割线
- (UIView *)topLine{
    
    if (!_topLine) {
        
        _topLine = [[UIView alloc]initWithFrame:CGRectMake(0, 0, kScreenWidth, 0.5)];
        _topLine.backgroundColor = [UIColor colorWithRed:165./255. green:165./255. blue:165./255. alpha:1.];
    }
    return _topLine;
}

-(UIButton *)voiceButton{
    if (!_voiceButton) {
        _voiceButton =[[UIButton alloc]initWithFrame:CGRectMake(0, (menuHeightMU - buttonHeightMU)/2, buttonHeightMU, buttonHeightMU)];
        [_voiceButton setImage:[UIImage imageNamed:@"ToolViewInputVoice"] forState:UIControlStateSelected];
        _voiceButton.selected = NO;
        [_voiceButton setImage:[UIImage imageNamed:@"ToolViewKeyboard"] forState:UIControlStateNormal];
        
        [_voiceButton addTarget:self action:@selector(voiceButtonDown:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _voiceButton;
}
-(UIButton *)faceButton{
    if (!_faceButton) {
        _faceButton =[[UIButton alloc]initWithFrame:CGRectMake(kScreenWidth -2 *buttonHeightMU, (menuHeightMU - buttonHeightMU)/2, buttonHeightMU, buttonHeightMU)];
        [_faceButton setImage:[UIImage imageNamed:@"ToolViewEmotion"] forState:UIControlStateNormal];
        [_faceButton setImage:[UIImage imageNamed:@"ToolViewKeyboard"] forState:UIControlStateSelected];
        [_faceButton setImage:[UIImage imageNamed:@"ToolViewEmotionHL"] forState:UIControlStateHighlighted];
        [_faceButton addTarget:self action:@selector(faceButtonDown:) forControlEvents:UIControlEventTouchUpInside];
        _faceButton.selected = NO;
    }
    return _faceButton;
}
-(UIButton *)moreButton{
    if (!_moreButton) {
        _moreButton =[[UIButton alloc]initWithFrame:CGRectMake(kScreenWidth - buttonHeightMU, (menuHeightMU - buttonHeightMU)/2, buttonHeightMU, buttonHeightMU)];
        [_moreButton setImage:[UIImage imageNamed:@"TypeSelectorBtn_Black"] forState:UIControlStateNormal];
        [_moreButton setImage:[UIImage imageNamed:@"TypeSelectorBtn_Black"] forState:UIControlStateSelected];
        [_moreButton setImage:[UIImage imageNamed:@"TypeSelectorBtnHL_Black"] forState:UIControlStateHighlighted];
        [_moreButton addTarget:self action:@selector(moreButtonDown:) forControlEvents:UIControlEventTouchUpInside];
        _moreButton.selected = NO;
        
    }
    return _moreButton;
}
-(UITextView *)textView{
    if (!_textView) {
        _textView =[[UITextView alloc]initWithFrame:CGRectMake(buttonHeightMU + 6., (menuHeightMU - 36.)/2, kScreenWidth -3 * buttonHeightMU - 2 *6., 36.)];
        _textView.font = [UIFont systemFontOfSize:16.];
        _textView.layer. masksToBounds = YES;
        _textView.layer.cornerRadius = 4.0f;
        _textView.layer.borderWidth = 0.5f;
        _textView.layer.borderColor= self.topLine.backgroundColor.CGColor;
        _textView.scrollsToTop = NO;
        _textView.returnKeyType = UIReturnKeySend;
        _textView.delegate = self;
    }
    return _textView;
}
-(UIButton *)talkButton{
    if (!_talkButton) {
        _talkButton = [[UIButton alloc]initWithFrame:self.textView.frame];
        [_talkButton setTitle:@"暂不支持语音通话" forState:UIControlStateNormal];
        //        [_talkButton setTitle:@"按住 说话" forState:UIControlStateNormal];
        //        [_talkButton setTitle:@"松开 结束" forState:UIControlStateHighlighted];
        [_talkButton setTitleColor:[UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0] forState:UIControlStateNormal];
        [_talkButton setBackgroundImage:[UIImage imageFromColorMu:[UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:0.5]] forState:UIControlStateHighlighted];
        _talkButton.layer. masksToBounds = YES;
        _talkButton.layer.cornerRadius = 4.0f;
        _talkButton.layer.borderWidth = 0.5f;
        [_talkButton.layer setBorderColor:self.topLine.backgroundColor.CGColor];
        [_talkButton setHidden:YES];
        //        [_talkButton addTarget:self action:@selector(talkButtonDown:) forControlEvents:UIControlEventTouchDown];
        //        [_talkButton addTarget:self action:@selector(talkButtonUpInside:) forControlEvents:UIControlEventTouchUpInside];
        //        [_talkButton addTarget:self action:@selector(talkButtonUpOutside:) forControlEvents:UIControlEventTouchUpOutside];
        //        [_talkButton addTarget:self action:@selector(talkButtonTouchCancel:) forControlEvents:UIControlEventTouchCancel];
        //        [_talkButton addTarget:self action:@selector(talkButtonDragOutside:) forControlEvents:UIControlEventTouchDragOutside];
        //        [_talkButton addTarget:self action:@selector(talkButtonDragInside:) forControlEvents:UIControlEventTouchDragInside];
    }
    return _talkButton;
}


- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.isUserInteractionEnabled || self.isHidden || self.alpha <= 0.01) {
        return nil;
    }
    if ([self pointInside:point withEvent:event]) {
        for (UIView *subview in [self.subviews reverseObjectEnumerator]) {
            CGPoint convertedPoint = [subview convertPoint:point fromView:self];
            UIView *hitTestView = [subview hitTest:convertedPoint withEvent:event];
            if (hitTestView) {
                
                return hitTestView;
            }
        }
        return self;
    }
    return nil;
}
@end
