#import "RPCS3UpstreamMenuModel.h"
#import "RPCS3UpstreamUIController.h"

static NSString *S(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSArray *A(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static NSDictionary *D(id value) { return [value isKindOfClass:NSDictionary.class] ? value : @{}; }

static NSDictionary *FindNode(NSDictionary *node, NSString *className, NSString *name) {
    if ((!className.length || [S(node[@"class"]) isEqualToString:className]) && (!name.length || [S(node[@"name"]) isEqualToString:name])) return node;
    for (NSDictionary *child in A(node[@"children"])) {
        NSDictionary *match = FindNode(child, className, name);
        if (match) return match;
    }
    return nil;
}

static UIAction *Action(NSString *identifier, NSDictionary *titles, RPCS3UpstreamMenuActionHandler handler) {
    NSDictionary *record = D(titles[identifier]);
    NSString *title = S(record[@"title"]);
    if (!title.length) title = identifier;
    UIAction *action = [UIAction actionWithTitle:title image:nil identifier:identifier handler:^(__kindof UIAction *sender) {
        (void)sender;
        if (handler) handler(identifier);
    }];
    if ([S(record[@"enabled"]) isEqualToString:@"false"]) action.attributes |= UIMenuElementAttributesDisabled;
    if ([S(record[@"checkable"]) isEqualToString:@"true"] && [S(record[@"checked"]) isEqualToString:@"true"]) action.state = UIMenuElementStateOn;
    return action;
}

static UIMenu *MenuFromNode(NSDictionary *node, NSDictionary *titles, RPCS3UpstreamMenuActionHandler handler) {
    NSMutableDictionary<NSString *, NSDictionary *> *submenus = [NSMutableDictionary dictionary];
    for (NSDictionary *child in A(node[@"children"])) if ([S(child[@"class"]) isEqualToString:@"QMenu"] && S(child[@"name"]).length) submenus[S(child[@"name"])] = child;

    NSMutableArray<UIMenuElement *> *result = [NSMutableArray array];
    NSMutableArray<UIMenuElement *> *segment = [NSMutableArray array];
    void (^flush)(void) = ^{
        if (!segment.count) return;
        [result addObject:[UIMenu menuWithTitle:@"" options:UIMenuOptionsDisplayInline children:[segment copy]]];
        [segment removeAllObjects];
    };

    NSArray *order = A(node[@"actions"]);
    if (!order.count) order = [submenus.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *identifier in order) {
        if ([identifier isEqualToString:@"separator"]) { flush(); continue; }
        NSDictionary *submenu = submenus[identifier];
        if (submenu) [segment addObject:MenuFromNode(submenu, titles, handler)];
        else [segment addObject:Action(identifier, titles, handler)];
    }
    flush();

    if (!result.count) {
        for (NSDictionary *submenu in submenus.allValues) [result addObject:MenuFromNode(submenu, titles, handler)];
    }
    NSString *title = S(node[@"title"]);
    if (!title.length) title = S(node[@"name"]);
    return [UIMenu menuWithTitle:title children:result];
}

UIMenu *RPCS3CreateUpstreamMainMenu(RPCS3UpstreamMenuActionHandler handler) {
    NSDictionary *mainDocument = nil;
    for (NSDictionary *document in A(RPCS3LoadBundledQtUIModel()[@"documents"])) {
        if ([S(document[@"file"]) isEqualToString:@"main_window.ui"]) { mainDocument = document; break; }
    }
    if (!mainDocument) {
        UIAction *missing = [UIAction actionWithTitle:@"RPCS3 UI model unavailable" image:nil identifier:@"modelUnavailable" handler:^(__kindof UIAction *action) { (void)action; }];
        missing.attributes = UIMenuElementAttributesDisabled;
        return [UIMenu menuWithTitle:@"RPCS3" children:@[missing]];
    }

    NSMutableDictionary *titles = [NSMutableDictionary dictionary];
    for (NSDictionary *action in A(mainDocument[@"actions"])) if (S(action[@"name"]).length) titles[S(action[@"name"])] = action;
    NSDictionary *menuBar = FindNode(D(mainDocument[@"root"]), @"QMenuBar", @"menuBar");
    if (!menuBar) return [UIMenu menuWithTitle:@"RPCS3" children:@[]];

    NSMutableArray<UIMenuElement *> *menus = [NSMutableArray array];
    NSMutableDictionary *byName = [NSMutableDictionary dictionary];
    for (NSDictionary *child in A(menuBar[@"children"])) if ([S(child[@"class"]) isEqualToString:@"QMenu"]) byName[S(child[@"name"])] = child;
    NSArray *order = A(menuBar[@"actions"]);
    if (order.count) {
        for (NSString *name in order) if (byName[name]) [menus addObject:MenuFromNode(byName[name], titles, handler)];
    } else {
        for (NSDictionary *child in A(menuBar[@"children"])) if ([S(child[@"class"]) isEqualToString:@"QMenu"]) [menus addObject:MenuFromNode(child, titles, handler)];
    }
    return [UIMenu menuWithTitle:@"RPCS3" children:menus];
}
