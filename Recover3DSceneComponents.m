function [annotation,valid] = Recover3DSceneComponents(annotation,Params3D,imageSize)
% Inputs:
% annotation - LabelMe annotation structure.
% Params3D - LabelMe3D parameters.
% imageSize - Image size [nrows ncols]
%
% Outputs:
% annotation - LabelMe annotation structure, augmented with 3D information.
% valid - Indicates whether output is valid.

validObjects = [];
for i = 1:length(annotation.object)
  if ~isfield(annotation.object(i),'world3d') || ~isfield(annotation.object(i).world3d,'stale') || strcmp(annotation.object(i).world3d.stale,'1')
    validObjects(end+1) = i;
  end
end

if ~isfield(annotation,'imagesize')
  annotation.imagesize.nrows = imageSize(1);
  annotation.imagesize.ncols = imageSize(2);
end
if isstr(annotation.imagesize.nrows)
  annotation.imagesize.nrows = str2num(annotation.imagesize.nrows);
end
if isstr(annotation.imagesize.ncols)
  annotation.imagesize.ncols = str2num(annotation.imagesize.ncols);
end

% Add object IDs:
for i = 1:length(annotation.object)
  annotation.object(i).id = num2str(i-1);
end
maxID = annotation.object(end).id;

% Get valid object indices:
dd = isdeleted(annotation);
validObjects = intersect(validObjects,find(dd==0)');

display(sprintf('Computing geometry for %d objects.',length(validObjects)));
% $$$ for i = 1:length(validObjects)
% $$$   display(sprintf('Valid object ID: %s',annotation.object(validObjects(i)).id));
% $$$ end

% Clean up object names:
annotation = myLMaddtags(annotation);

if length(validObjects)>0
  % Infer posterior of parts:
  annotation = inferPartsPosterior(annotation,Params3D.Ppart,Params3D.objectClasses,validObjects);
  
  % Infer edges types:
  annotation = inferEdgeTypesNew(annotation,validObjects);
else
  display('Skipping part-of and edge type inference...');
end

% Make sure all standing objects make contact with the ground:
for i = validObjects
  if strcmp(annotation.object(i).polygon.polyType,'standing') && isempty(getLMcontact(annotation.object(i).polygon))
    annotation.object(i).polygon.polyType = '';
  end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Convert XML file to new format:
for i = validObjects%1:length(annotation.object)
  annotation.object(i).world3d.stale = '0';
  annotation.object(i).world3d.type = '';

  % annotation.object.polygon.polyType -> annotation.object.world3d.type
  if isfield(annotation.object(i),'polygon') && isfield(annotation.object(i).polygon,'polyType')
    switch annotation.object(i).polygon.polyType
     case 'standing'
      annotation.object(i).world3d.type = 'standingplanes';
     case 'part'
      annotation.object(i).world3d.type = 'part';
     case 'ground'
      annotation.object(i).world3d.type = 'groundplane';
     otherwise
      annotation.object(i).world3d.type = 'none';
    end
    annotation.object(i).polygon = rmfield(annotation.object(i).polygon,'polyType');
  end

  % annotation.object.polygon.contact -> annotation.object.world3d.contact
  if isfield(annotation.object(i),'polygon') && isfield(annotation.object(i).polygon,'contact')
    annotation.object(i).world3d.contact = annotation.object(i).polygon.contact;
    annotation.object(i).polygon = rmfield(annotation.object(i).polygon,'contact');
  end

  % annotation.object.partof -> annotation.object.world3d.partof
  if isfield(annotation.object(i),'partof') && ~isempty(annotation.object(i).partof)
    annotation.object(i).world3d.parentid = annotation.object(i).partof;
  end
end
if isfield(annotation.object,'partof')
  annotation.object = rmfield(annotation.object,'partof');
end

% Find camera parameters:
annotation = getviewpoint(annotation,Params3D.ObjectHeights);

% Get indices of non-deleted objects:
notDeleted = find(~isdeleted(annotation))';

% Convert image size to strings:
annotation.imagesize.nrows = num2str(annotation.imagesize.nrows);
annotation.imagesize.ncols = num2str(annotation.imagesize.ncols);

valid = 0;
for i = notDeleted
% $$$   if strcmp(annotation.object(i).polygon.polyType,'ground')
  if strcmp(annotation.object(i).world3d.type,'groundplane')
    valid = 1;
  end
end

Hy = str2num(annotation.camera.Hy)/imageSize(1);
if (Hy < 0.05) || (Hy > 0.95)
  display('Horizon line is out of range.');
  valid = 0;
end

% Restore original object names:
for i = 1:length(annotation.object)
  annotation.object(i).name = annotation.object(i).originalname;
end

% Remove "originalname" field:
annotation.object = rmfield(annotation.object,'originalname');

% annotation.camera
P = getCameraMatrix(annotation);

% Store camera matrix:
annotation.camera.units = 'centimeters';
annotation.camera.pmatrix.p11 = num2str(P(1,1));
annotation.camera.pmatrix.p12 = num2str(P(1,2));
annotation.camera.pmatrix.p13 = num2str(P(1,3));
annotation.camera.pmatrix.p14 = num2str(P(1,4));
annotation.camera.pmatrix.p21 = num2str(P(2,1));
annotation.camera.pmatrix.p22 = num2str(P(2,2));
annotation.camera.pmatrix.p23 = num2str(P(2,3));
annotation.camera.pmatrix.p24 = num2str(P(2,4));
annotation.camera.pmatrix.p31 = num2str(P(3,1));
annotation.camera.pmatrix.p32 = num2str(P(3,2));
annotation.camera.pmatrix.p33 = num2str(P(3,3));
annotation.camera.pmatrix.p34 = num2str(P(3,4));

% Remove old extra fields:
if isfield(annotation.camera,'Hy')
  annotation.camera = rmfield(annotation.camera,'Hy');
end
if isfield(annotation.camera,'CAM_H')
  annotation.camera = rmfield(annotation.camera,'CAM_H');
end
if isfield(annotation.camera,'F')
  annotation.camera = rmfield(annotation.camera,'F');
end

% Remove points that have been added before:
for i = notDeleted
  switch annotation.object(i).world3d.type
   case {'standingplanes','part'}
    if isfield(annotation.object(i).world3d,'polygon3d')
      nAdded = logical(str2num(char({annotation.object(i).world3d.polygon3d.pt.added})));
      annotation.object(i).polygon.pt(nAdded) = [];
      annotation.object(i).world3d.polygon3d.pt(nAdded) = [];
    end
  end
end


% Add 3D information for groundplane and standingplanes objects:
P = getCameraMatrix(annotation);
[K,R,C] = decomposeP(P);
for i = notDeleted%1:length(annotation.object)
  switch annotation.object(i).world3d.type
   case 'groundplane'
    % Intersect polygon points with ground plane:
    [x,y] = getLMpolygon(annotation.object(i).polygon);
    [x,y] = LH2RH(x,y,imageSize);
    X = projectOntoGroundPlane(x,y,annotation);
    annotation.object(i).world3d.polygon3d = setLMpolygon3D(X(1,:),X(2,:),X(3,:));

    % Get plane parameters:
    annotation.object(i).world3d.plane.pix = '0';
    annotation.object(i).world3d.plane.piy = '1';
    annotation.object(i).world3d.plane.piz = '0';
    annotation.object(i).world3d.plane.piw = '0';

    % Reorder fields:
    annotation.object(i).world3d = orderfields(annotation.object(i).world3d,{'type','stale','polygon3d','plane'});
   case 'standingplanes'
    % Get planes corresponding to each contact edge by reasoning through
    % world contact lines:
    [x,y] = getLMpolygon(annotation.object(i).polygon);
    [x,y] = LH2RH(x,y,imageSize);
    xc = str2num(char({annotation.object(i).world3d.contact(:).x}));
    yc = str2num(char({annotation.object(i).world3d.contact(:).y}));
    [xc,yc] = LH2RH(xc,yc,imageSize);

    % Get plane parameters:
    H = P(:,[1 3 4]);
    if length(xc)==1
      % Make single plane frontal-parallel:
      xx = H\[xc yc 1]';
      PI = [0 0 1 -xx(2)/xx(3)]';
    else
      % Handle multiple planes:
      PI = [];
      for j = 1:length(xc)-1
        x1 = [xc(j) yc(j) 1]';
        x2 = [xc(j+1) yc(j+1) 1]';
        li = cross(x1,x2);
        lw = H'*li;
        lw = lw/sqrt(lw(1)^2+lw(2)^2);
        PI(:,j) = [lw(1) 0 lw(2) lw(3)]';
      end
    end

    % Project 2D points onto standing planes:
    [X,isAdded,nPlane,x,y] = projectOntoStandingPlanes(x,y,P,PI,xc,yc,i);
    
    if ~isempty(X)
      if any(isAdded)
        % Store 2D points:
        [x,y] = RH2LH(x,y,imageSize);
        for j = 1:length(x)
          annotation.object(i).polygon.pt(j).x = num2str(x(j));
          annotation.object(i).polygon.pt(j).y = num2str(y(j));
        end
      end
      
      % Store plane parameters:
      for j = 1:size(PI,2)
        annotation.object(i).world3d.plane(j).pix = num2str(PI(1,j));
        annotation.object(i).world3d.plane(j).piy = num2str(PI(2,j));
        annotation.object(i).world3d.plane(j).piz = num2str(PI(3,j));
        annotation.object(i).world3d.plane(j).piw = num2str(PI(4,j));
      end
    
      % Store 3D points in annotation structure:
      annotation.object(i).world3d.polygon3d = setLMpolygon3D(X(1,:),X(2,:),X(3,:));
      for j = 1:size(X,2)
        annotation.object(i).world3d.polygon3d.pt(j).added = num2str(isAdded(j));
        for k = 1:length(nPlane{j})
          annotation.object(i).world3d.polygon3d.pt(j).planeindex(k).index = num2str(nPlane{j}(k)-1);
        end
      end
      
      % Reorder fields:
      annotation.object(i).world3d = orderfields(annotation.object(i).world3d,{'type','stale','polygon3d','contact','plane'});
% $$$     else
% $$$       keyboard;
    end
   case 'part'
    % Reorder fields:
    annotation.object(i).world3d = orderfields(annotation.object(i).world3d,{'type','stale','parentid'});
   case 'none'
    % Reorder fields:
    annotation.object(i).world3d = orderfields(annotation.object(i).world3d,{'type','stale'});
  end
end

% Add 3D information for parts:
for i = notDeleted%1:length(annotation.object)
  if strcmp(annotation.object(i).world3d.type,'part')
    % Get root object index:
    k = getPartOfParents(annotation,i);
    nRoot = k(end);

    % Set root ID:
    annotation.object(i).world3d.rootid = annotation.object(nRoot).id;
    
    if isfield(annotation.object(nRoot).world3d,'polygon3d')
      % Get polygon:
      [x,y] = getLMpolygon(annotation.object(i).polygon);
      [x,y] = LH2RH(x,y,imageSize);

      switch annotation.object(nRoot).world3d.type
       case 'standingplanes'
        % Project 2D points onto root object's standing planes:
        [X,isAdded,nPlane,x,y] = projectOntoStandingPlanes(x,y,annotation,nRoot);
       case 'groundplane'
        [X,isAdded,nPlane,x,y] = projectOntoGroundPlane(x,y,annotation);
% $$$         H = P(:,[1 3 4]);
% $$$         X = H\[x(:) y(:) ones(length(x),1)]';
% $$$         X = [X(1,:)./X(3,:); zeros(1,length(x)); X(2,:)./X(3,:)];
% $$$         isAdded = zeros(1,length(x));
% $$$         nPlane = cell(1,length(x));
% $$$         nPlane(:) = {1};
       otherwise
        error('Root object 3D type is invalid');
      end
      
      if ~isempty(X)
        if any(isAdded)
          % Store 2D points:
          [x,y] = RH2LH(x,y,imageSize);
          for j = 1:length(x)
            annotation.object(i).polygon.pt(j).x = num2str(x(j));
            annotation.object(i).polygon.pt(j).y = num2str(y(j));
          end
        end
        
        % Store 3D points in annotation structure:
        annotation.object(i).world3d.polygon3d = setLMpolygon3D(X(1,:),X(2,:),X(3,:));
        for j = 1:size(X,2)
          annotation.object(i).world3d.polygon3d.pt(j).added = num2str(isAdded(j));
          for k = 1:length(nPlane{j})
            annotation.object(i).world3d.polygon3d.pt(j).planeindex(k).index = num2str(nPlane{j}(k)-1);
          end
        end
      end
    end
  end
end