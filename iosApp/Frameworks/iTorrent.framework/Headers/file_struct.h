//
//  file_struct.h
//  iTorrent
//
//  Created by  XITRIX on 15.05.2018.
//  Copyright © 2018  XITRIX. All rights reserved.
//

#ifndef file_struct_h
#define file_struct_h

typedef struct File {
    char * _Nullable file_name;
    long long file_size;
    long long file_downloaded;
    int file_priority;
    long long begin_idx;
    long long end_idx;
    int num_pieces;
    int * _Nullable pieces;
} File;

typedef struct Files {
    int error;
    int size;
    char* _Nullable title;
    File* _Nullable files;
} Files;

typedef struct Tracker {
    char * _Nullable tracker_url;
    char * _Nullable messages;
    int seeders;
    int peers;
    int leechs;
    int working;
    int verified;
} Tracker;

typedef struct Trackers {
	int size;
    Tracker * _Nullable trackers;
} Trackers;
#endif /* file_struct_h */
