#import "CCNodeAR.h"

#import "Tools.h"
#import "CCNavigationControllerAR.h"

@interface CCNodeAR (Private)
-(GLKVector3)unprojectScreenCoords:(GLKVector3)screenPt
                        mvpInverse:(const GLKMatrix4 *)mvpInvMat
                          viewport:(const GLKVector4 *)viewport;

-(float)distanceOfPoint:(const GLKVector3 *)x0
             toLineFrom:(const GLKVector3 *)x1 to:(const GLKVector3 *)x2;
@end

@implementation CCNodeAR

@synthesize objectId = _objectId;
//@synthesize arTranslationVec;
@synthesize scaleZ = _scaleZ;
@synthesize userInteractionRadiusFactor = _userInteractionRadiusFactor;

#pragma mark init/dealloc

-(id)init {
    self = [super init];
    if (self) {
        _scaleZ = 1.0f;
        _userInteractionRadiusFactor = 1.0f;
        _initializedForUserInteraction = NO;
    }
    
    return self;
}

#pragma mark public methods

-(void)setARTransformMatrix:(const float [16])m {
    memcpy(_arTransformMat, m, 16 * sizeof(float));
    _arTransformGLKMat = GLKMatrix4MakeWithArray(_arTransformMat);
}

-(const GLKMatrix4 *)arTransformMatrixPtr {
    return &_arTransformGLKMat;
}

-(BOOL)initForUserInteraction {
    CCDirector *director = [CCDirector sharedDirector];
    if (![[director delegate] isKindOfClass:[CCNavigationControllerAR class]]) {
        NSLog(@"CCNodeAR: Navigation controller must be of type 'CCNavigationControllerAR' for hit test");
        return NO;
    }
    
    CCNavigationControllerAR *navCtrl = (CCNavigationControllerAR *)[director delegate];
    
    _projMat = director.projectionMatrix;
    _glViewportSpecs = navCtrl.glViewportSpecs;

    _initializedForUserInteraction = YES;
    
    return YES;
}

-(BOOL)hitTest3DWithTouchPoint:(CGPoint)pos useTransform:(const GLKMatrix4 *)useTransMat {
    NSAssert(_initializedForUserInteraction, @"CCNodeAR: must be initialized for user interaction");
    
    // apply screen scale to touch point
    float sf = [CCNavigationControllerAR uiScreenScale];
    pos = CGPointMake(pos.x * sf, pos.y * sf);  // pos is now in pixels
    NSLog(@"CCNodeAR: touch point at %d, %d px", (int)pos.x, (int)pos.y);
    
    // get the model-view transform matrix
    GLKMatrix4 mvMat = _arTransformGLKMat;

    
    // get the inverse of the model-view-projection matrix
    bool isInv;
    GLKMatrix4 mvpInvMat = GLKMatrix4Invert(GLKMatrix4Multiply(_projMat, mvMat), &isInv);
    if (!isInv) {
        NSLog(@"CCNodeAR: Could not invert MVP matrix for hit test");
        return NO;
    }
    
    // construct a ray into the 3D scene
    GLKVector3 rayPt1 = [self unprojectScreenCoords:GLKVector3Make(pos.x, pos.y, 0.0f)  // point at near plane
                                         mvpInverse:&mvpInvMat
                                           viewport:&_glViewportSpecs];
    GLKVector3 rayPt2 = [self unprojectScreenCoords:GLKVector3Make(pos.x, pos.y, 1.0f)  // point at far plane
                                         mvpInverse:&mvpInvMat
                                           viewport:&_glViewportSpecs];
    
    GLKVector3 rayDir = GLKVector3Normalize(GLKVector3Subtract(rayPt2, rayPt1));

    NSLog(@"CCNodeAR: Ray for hit test is o=[%f, %f, %f], l=[%f, %f, %f]",
          rayPt1.x, rayPt1.y, rayPt1.z,
          rayDir.x, rayDir.y, rayDir.z);
    
    GLKVector3 origin = GLKVector3Make(0.0f, 0.0f, 0.0f);
    
    float dist = [self distanceOfPoint:&origin toLineFrom:&rayPt1 to:&rayPt2];
    
    NSLog(@"CCNodeAR: distance = %f", dist);
    
    return (dist <= (self.scale / 2.0f) * _userInteractionRadiusFactor);
}

#pragma mark parent methods

-(void)setUserInteractionEnabled:(BOOL)userInteractionEnabled {
    if ([self initForUserInteraction]) {
        [super setUserInteractionEnabled:userInteractionEnabled];
    }
}

-(void)setScale:(float)scale {
    _scaleZ = scale;
    [super setScale:scale];
}

-(void)visit:(__unsafe_unretained CCRenderer *)renderer parentTransform:(const GLKMatrix4 *)parentTransform
{
	// quick return if not visible. children won't be drawn.
	if (!_visible)
		return;
    
    [self sortAllChildren];
    
    // just use the AR transform matrix directly for this node
    GLKMatrix4 transform = GLKMatrix4Multiply(*parentTransform, _arTransformGLKMat);
    
    // additionally apply a scale matrix
	GLKMatrix4 scaleMat = GLKMatrix4MakeScale(_scaleX, _scaleY, _scaleZ);
    transform = GLKMatrix4Multiply(transform, scaleMat);
    
//    NSLog(@"CCNodeAR - transform:");
//    [Tools printGLKMat4x4:&transform];
    
	BOOL drawn = NO;
    
	for(CCNode *child in _children){
		if(!drawn && child.zOrder >= 0){
			[self draw:renderer transform:&transform];
			drawn = YES;
		}
        
		[child visit:renderer parentTransform:&transform];
    }
    
	if(!drawn) [self draw:renderer transform:&transform];
    
	// reset for next frame
	_orderOfArrival = 0;
}

- (void) sortAllChildren
{
    // copy&paste from CCNode. necessary because this method was private and is called from
    // visit:parentTransform:
    
	if (_isReorderChildDirty)
	{
        [_children sortUsingSelector:@selector(compareZOrderToNode:)];
        
		//don't need to check children recursively, that's done in visit of each child
        
		_isReorderChildDirty = NO;
        
        [[[CCDirector sharedDirector] responderManager] markAsDirty];
        
	}
}

#pragma mark private methods

-(GLKVector3)unprojectScreenCoords:(GLKVector3)screenPt
                        mvpInverse:(const GLKMatrix4 *)mvpInvMat
                          viewport:(const GLKVector4 *)viewport
{
    // transform screen point (which is in pixels with [0,0] at *upper* left)
    // to normalized coordinates with:
    // [-1,-1] at lower left
    // [+1,+1] at upper right
    GLKVector4 n = GLKVector4Make(screenPt.x, screenPt.y, screenPt.z, 1.0f);
    n.x = (n.x - viewport->v[0]) / viewport->v[2];
    n.y = (n.y - viewport->v[1]) / viewport->v[3];
    n = GLKVector4MultiplyScalar(n, 2.0f);
    n = GLKVector4AddScalar(n, -1.0f);
    n.y *= -1.0f;
    
    NSLog(@"CCNodeAR: unproject normalized vector = [%f, %f, %f, %f]",
          n.x, n.y, n.z, n.w);
    
    // transform the normalized coordinates by the inverse model-view-projection matrix
    n = GLKMatrix4MultiplyVector4(*mvpInvMat, n);
    
    // form a 3-component vector and return it
    return GLKVector3Make(n.x / n.w, n.y / n.w, n.z / n.w);
}

-(float)distanceOfPoint:(const GLKVector3 *)x0
             toLineFrom:(const GLKVector3 *)x1 to:(const GLKVector3 *)x2
{
    GLKVector3 x1x0 = GLKVector3Subtract(*x0, *x1);
    GLKVector3 x2x0 = GLKVector3Subtract(*x0, *x2);
    GLKVector3 num = GLKVector3CrossProduct(x1x0, x2x0);
    GLKVector3 x1x2 = GLKVector3Subtract(*x2, *x1);
    
    return GLKVector3Length(num) / GLKVector3Length(x1x2);
}

@end
